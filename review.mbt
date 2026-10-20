///|
priv enum Command {
  Index(Bool)
  Reindex(Bool, Bool)
  RenameIndex
  MoveIndex
  LockTable(LockMode, Bool)
  Analyze(skip_locked~ : Bool, database_wide~ : Bool)
  Cluster(database_wide~ : Bool)
  Refresh(concurrent~ : Bool, no_data~ : Bool)
  ValidateConstraint
  Vacuum(
    full~ : Bool,
    skip_locked~ : Bool,
    truncate~ : Bool,
    cleanup_off~ : Bool,
    database_wide~ : Bool
  )
  InvalidIndex(String)
  Begin(read_only~ : Bool, deferrable~ : Bool)
  Finish(rollback~ : Bool, chain~ : Bool)
  SetTimeout(scoped~ : Bool, Timeout)
  Savepoint(String)
  RollbackTo(String)
  Release(String)
  Unsupported
}

///|
priv enum Transaction {
  Idle
  Implicit
  Explicit
  External
  Uncertain
} derive(Eq)

///|
// A deliberately closed grammar for state-changing statements. The dependency
// validates index syntax; unrecognized SQL never becomes an assumed no-op.
fn classify(fragment : Fragment) -> Command {
  match fragment.words[:] {
    ["SET", "LOCAL", "LOCK_TIMEOUT", "=" | "TO", value] =>
      match parse_timeout(value) {
        Some(t) => SetTimeout(scoped=true, t)
        None => Unsupported
      }
    ["SET", "SESSION", "LOCK_TIMEOUT", "=" | "TO", value]
    | ["SET", "LOCK_TIMEOUT", "=" | "TO", value] =>
      match parse_timeout(value) {
        Some(t) => SetTimeout(scoped=false, t)
        None => Unsupported
      }
    ["RESET", "LOCK_TIMEOUT" | "ALL"] => SetTimeout(scoped=false, Default)
    ["SAVEPOINT", name] =>
      match savepoint_name(name) {
        Some(n) => Savepoint(n)
        None => Unsupported
      }
    ["RELEASE", name] | ["RELEASE", "SAVEPOINT", name] =>
      match savepoint_name(name) {
        Some(n) => Release(n)
        None => Unsupported
      }
    ["ROLLBACK", "TO", name] | ["ROLLBACK", "TO", "SAVEPOINT", name] =>
      match savepoint_name(name) {
        Some(n) => RollbackTo(n)
        None => Unsupported
      }
    ["BEGIN", .. rest] => {
      let modes = match rest {
        ["WORK" | "TRANSACTION", .. tail] => tail
        _ => rest
      }
      classify_begin(modes)
    }
    ["START", "TRANSACTION", .. modes] => classify_begin(modes)
    ["COMMIT" | "END" | "ROLLBACK" | "ABORT", .. rest] => {
      let suffix = match rest {
        ["WORK" | "TRANSACTION", .. tail] => tail
        _ => rest
      }
      let chain = match suffix {
        [] | ["AND", "NO", "CHAIN"] => false
        ["AND", "CHAIN"] => true
        _ => return Unsupported
      }
      Finish(
        rollback=fragment.words[0] == "ROLLBACK" || fragment.words[0] == "ABORT",
        chain~,
      )
    }
    ["DROP", "INDEX", ..] => classify_drop(fragment.words[:])
    ["ALTER", "INDEX", ..] => classify_alter_index(fragment.words[:])
    ["ALTER", "TABLE", ..] => classify_validate_constraint(fragment.words[:])
    ["REINDEX", ..] => classify_reindex(fragment.words[:])
    ["LOCK", ..] => classify_lock(fragment.words[:])
    ["ANALYZE", ..] => classify_analyze(fragment.words[:])
    ["VACUUM", ..] => classify_vacuum(fragment.words[:])
    ["CLUSTER", ..] => classify_cluster(fragment.words[:])
    ["REFRESH", "MATERIALIZED", "VIEW", ..] =>
      classify_refresh(fragment.words[:])
    ["CREATE", ..] => {
      let mut depth = 0
      for word in fragment.words {
        if word == "(" {
          depth += 1
        } else if word == ")" {
          depth -= 1
        }
        if depth < 0 || depth > 128 {
          return Unsupported
        }
      }
      if depth != 0 {
        return Unsupported
      }
      let parsed = @sql.parse_sql(dialect=@sql.Postgres::{ }, fragment.text) catch {
        _ => return Unsupported
      }
      match parsed.stmts[:] {
        [@sql.CreateIndex(index)] => Index(index.concurrently)
        _ => Unsupported
      }
    }
    _ => Unsupported
  }
}

///|
/// Analyze PostgreSQL 18 index statements, maintenance, locks and transactions.
/// The caller must describe dispatch; comments never override the execution mode.
/// A positive max_lock_timeout_ms also enables timeout checking. Invalid limits
/// yield ML011 and an incomplete report without analyzing statements.
/// initial_lock_timeout_ms is a caller-assured session value with no unmodeled
/// SET LOCAL override. Existing-transaction rollback has an unknown earlier
/// baseline. Negative initial values yield ML012 without analyzing statements.
pub fn review_sql(
  source : String,
  execution~ : Execution,
  initial_transaction~ : Bool = false,
  require_lock_timeout~ : Bool = false,
  max_lock_timeout_ms? : Int32,
  initial_lock_timeout_ms? : Int32,
) -> Report {
  if max_lock_timeout_ms is Some(limit) && limit <= 0 {
    return {
      source,
      statements: 0,
      complete: false,
      diagnostics: [
        finding(
          "ML011",
          Incomplete,
          { start: 0, end: source.length(), },
          "max_lock_timeout_ms must be a positive 32-bit integer",
          "Use a limit from 1 through 2147483647 milliseconds, or omit the maximum.",
        ),
      ],
    }
  }
  if initial_lock_timeout_ms is Some(value) && value < 0 {
    return {
      source,
      statements: 0,
      complete: false,
      diagnostics: [
        finding(
          "ML012",
          Incomplete,
          { start: 0, end: source.length(), },
          "initial_lock_timeout_ms must be a nonnegative 32-bit integer",
          "Supply an assured session-level value from 0 through 2147483647, or omit it when unknown.",
        ),
      ],
    }
  }
  let scanned = scan(source)
  let diagnostics = scanned.errors.copy()
  let mut complete = diagnostics.is_empty()
  let mut tx : Transaction = if execution == Unknown {
    Uncertain
  } else if execution == ExistingTransaction || initial_transaction {
    External
  } else {
    Idle
  }
  let batch = execution == SimpleQuery && scanned.fragments.length() > 1
  let mut open_span : Span = { start: 0, end: 0, }
  let timeouts = TimeoutState::new(initial_lock_timeout_ms)
  if execution == Unknown {
    complete = false
    diagnostics.push(
      finding(
        "ML010",
        Incomplete,
        { start: 0, end: source.length(), },
        "Execution mode is unknown",
        "Declare separate dispatch, one simple-query message, or an existing transaction.",
      ),
    )
  }
  for fragment in scanned.fragments {
    // PostgreSQL begins an implicit block for each transaction segment in a
    // multi-statement simple-query message, including after an explicit COMMIT.
    if batch && tx == Idle {
      timeouts.begin()
      tx = Implicit
    }
    let command = classify(fragment)
    match command {
      Begin(read_only~, deferrable~) => {
        if read_only {
          diagnostics.push(
            finding(
              "ML130",
              Warning,
              fragment.span,
              "READ ONLY restricts DDL and writes",
              "Review DDL permissions and transaction characteristics. This review does not enforce read-only restrictions; nested BEGIN does not change existing transaction characteristics.",
            ),
          )
        }
        if deferrable {
          diagnostics.push(
            finding(
              "ML131",
              Warning,
              fragment.span,
              "DEFERRABLE can wait for a safe snapshot in a SERIALIZABLE READ ONLY transaction",
              "Budget snapshot wait separately from lock_timeout. DEFERRABLE has no effect in other modes; runner defaults and existing transaction characteristics are not inferred.",
            ),
          )
        }
        if tx == Explicit || tx == External {
          diagnostics.push(
            finding(
              "ML104",
              Warning,
              fragment.span,
              "BEGIN does not create a nested transaction",
              "Use SAVEPOINT when a nested rollback boundary is required.",
            ),
          )
        } else if tx != Uncertain {
          if tx == Idle {
            timeouts.begin()
          }
          tx = Explicit
          open_span = fragment.span
        }
      }
      Finish(rollback~, chain~) => {
        if chain && (tx == Idle || tx == Implicit) {
          diagnostics.push(
            finding(
              "ML106",
              Error,
              fragment.span,
              "AND CHAIN requires an explicit transaction",
              "Begin an explicit transaction before chaining; an implicit simple-query block is insufficient.",
            ),
          )
          timeouts.taint()
          tx = Uncertain
          continue
        }
        if tx == Uncertain {
          timeouts.taint()
        } else if tx != Idle {
          timeouts.finish(rollback~)
        }
        if tx == Idle {
          diagnostics.push(
            finding(
              "ML104",
              Warning,
              fragment.span,
              "Transaction end has no active transaction",
              "Check the runner's transaction boundary.",
            ),
          )
        }
        if tx == External {
          diagnostics.push(
            finding(
              "ML105",
              Warning,
              fragment.span,
              "SQL ends the caller's existing transaction",
              "Confirm the runner permits migration SQL to close its transaction.",
            ),
          )
        }
        // Unknown SQL can also change the session; do not restore certainty.
        if tx != Uncertain {
          if chain {
            timeouts.begin()
            tx = Explicit
            open_span = fragment.span
          } else {
            tx = Idle
          }
        }
      }
      InvalidIndex(message) => {
        diagnostics.push(
          finding(
            "ML107",
            Error,
            fragment.span,
            message,
            "DROP INDEX CONCURRENTLY accepts one index and no CASCADE; split names into separately dispatched statements and inspect dependencies.",
          ),
        )
        timeouts.taint()
        tx = Uncertain
      }
      LockTable(mode, nowait) => {
        if tx == Idle || tx == Uncertain {
          let uncertain = tx == Uncertain
          diagnostics.push(
            finding(
              "ML121",
              if uncertain {
                Incomplete
              } else {
                Error
              },
              fragment.span,
              if uncertain {
                "Cannot establish transaction context for LOCK TABLE"
              } else {
                "LOCK TABLE requires an active transaction block"
              },
              "Begin a transaction, declare an existing transaction, or send a multi-statement simple-query message; a separately dispatched idle LOCK fails.",
            ),
          )
          if uncertain {
            complete = false
          }
          timeouts.taint()
          tx = Uncertain
        } else if !nowait &&
          (require_lock_timeout || max_lock_timeout_ms is Some(_)) {
          timeouts.check(fragment.span, diagnostics, max_lock_timeout_ms)
        }
        diagnostics.push(
          finding(
            "ML120",
            Warning,
            fragment.span,
            "LOCK TABLE requests \{mode.name()}: \{mode.impact()}",
            (if nowait {
              "NOWAIT rejects conflicting table-lock acquisition immediately; it does not shorten lock lifetime. "
            } else {
              "Review lock acquisition waits and acquisition order. "
            }) +
            "Acquired locks are normally held until transaction end; rollback to an earlier savepoint can release them. Check descendant/view expansion, privileges and workload manually.",
          ),
        )
      }
      ValidateConstraint => {
        if require_lock_timeout || max_lock_timeout_ms is Some(_) {
          timeouts.check(fragment.span, diagnostics, max_lock_timeout_ms)
        }
        constraint_validation_findings(fragment.span, diagnostics)
      }
      Refresh(concurrent~, no_data~) =>
        if concurrent && no_data {
          diagnostics.push(
            finding(
              "ML173",
              Error,
              fragment.span,
              "CONCURRENTLY and WITH NO DATA cannot be combined",
              "Use a populated view with CONCURRENTLY WITH DATA, or a non-concurrent WITH NO DATA operation with a planned reader outage. Resolve this server error before assuming later SQL executes.",
            ),
          )
          timeouts.taint()
          tx = Uncertain
        } else {
          if require_lock_timeout || max_lock_timeout_ms is Some(_) {
            timeouts.check(fragment.span, diagnostics, max_lock_timeout_ms)
          }
          refresh_findings(concurrent, no_data, fragment.span, diagnostics)
        }
      Cluster(database_wide~) => {
        if require_lock_timeout || max_lock_timeout_ms is Some(_) {
          timeouts.check(fragment.span, diagnostics, max_lock_timeout_ms)
        }
        if database_wide && tx != Idle {
          let uncertain = tx == Uncertain
          diagnostics.push(
            finding(
              "ML162",
              if uncertain {
                Incomplete
              } else {
                Error
              },
              fragment.span,
              if uncertain {
                "Cannot establish transaction context for database-wide CLUSTER"
              } else {
                "Database-wide CLUSTER cannot run in a transaction block"
              },
              "Dispatch it separately outside explicit/caller transactions and multi-statement simple-query blocks. A named ordinary table can be clustered in a transaction; partitioned tables cannot.",
            ),
          )
          if uncertain {
            complete = false
          }
          timeouts.taint()
          tx = Uncertain
        }
        cluster_findings(database_wide, fragment.span, diagnostics)
      }
      Vacuum(full~, skip_locked~, truncate~, cleanup_off~, database_wide~) => {
        if require_lock_timeout || max_lock_timeout_ms is Some(_) {
          timeouts.check(fragment.span, diagnostics, max_lock_timeout_ms)
        }
        if tx != Idle {
          let uncertain = tx == Uncertain
          diagnostics.push(
            finding(
              "ML151",
              if uncertain {
                Incomplete
              } else {
                Error
              },
              fragment.span,
              if uncertain {
                "Cannot establish transaction context for VACUUM"
              } else {
                "VACUUM cannot run in a transaction block"
              },
              "Dispatch VACUUM separately outside caller or explicit transactions; multi-statement simple-query messages also form transaction blocks. Resolve coverage before assuming later SQL executes.",
            ),
          )
          if uncertain {
            complete = false
          }
          timeouts.taint()
          tx = Uncertain
        }
        diagnostics.push(
          finding(
            "ML150",
            Warning,
            fragment.span,
            if full {
              "VACUUM FULL rewrites the table and requires ACCESS EXCLUSIVE locks"
            } else {
              "VACUUM performs ordinary maintenance with SHARE UPDATE EXCLUSIVE locks"
            },
            (if full {
              "Plan for blocked reads/writes, rewrite duration and temporary extra disk space. "
            } else {
              "Review contention with concurrent maintenance/schema changes and tuple/index processing work. "
            }) +
            (if skip_locked {
              "SKIP_LOCKED can omit busy relations and still wait on indexes or sample rows. "
            } else {
              ""
            }) +
            "lock_timeout bounds individual lock waits, not total maintenance duration. Relation kinds, privileges, workload and reclaimed space are not inferred.",
          ),
        )
        if !full && truncate {
          diagnostics.push(
            finding(
              "ML152",
              Warning,
              fragment.span,
              "Ordinary VACUUM may request ACCESS EXCLUSIVE for tail-page truncation",
              "TRUNCATE FALSE avoids this truncation lock; omitted TRUNCATE depends on server/table settings. This does not remove other maintenance waits or guarantee returned disk space.",
            ),
          )
        }
        if !full && cleanup_off {
          diagnostics.push(
            finding(
              "ML153",
              Warning,
              fragment.span,
              "INDEX_CLEANUP OFF skips normal index vacuuming",
              "Budget follow-up index cleanup and monitor dead tuples/bloat. AUTO/ON still do not guarantee cleanup: catalog facts and the wraparound failsafe can change actual work.",
            ),
          )
        }
        if database_wide {
          diagnostics.push(
            finding(
              "ML154",
              Warning,
              fragment.span,
              "VACUUM without a relation list has database-wide scope",
              "Name intended relations to bound maintenance work; actual processed relations depend on privileges and catalog state.",
            ),
          )
        }
      }
      Analyze(skip_locked~, database_wide~) => {
        if require_lock_timeout || max_lock_timeout_ms is Some(_) {
          timeouts.check(fragment.span, diagnostics, max_lock_timeout_ms)
        }
        diagnostics.push(
          finding(
            "ML140",
            Warning,
            fragment.span,
            "ANALYZE collects planner statistics and acquires SHARE UPDATE EXCLUSIVE locks",
            (if skip_locked {
              "SKIP_LOCKED may omit busy relations but can still wait on indexes or sample rows; it does not replace lock_timeout. "
            } else {
              "Budget lock waits and sampling work. "
            }) +
            "Review maintenance/schema contention, privileges, relation kind and descendant expansion; statistics and plan changes are not predicted.",
          ),
        )
        if database_wide {
          diagnostics.push(
            finding(
              "ML141",
              Warning,
              fragment.span,
              "ANALYZE without a relation list has database-wide scope",
              "Name the intended relations and columns to bound maintenance work. Privilege checks may cause relations to be skipped; coverage of database contents is not inferred.",
            ),
          )
        }
      }
      MoveIndex => {
        if require_lock_timeout || max_lock_timeout_ms is Some(_) {
          timeouts.check(fragment.span, diagnostics, max_lock_timeout_ms)
        }
        diagnostics.push(
          finding(
            "ML112",
            Warning,
            fragment.span,
            "Index tablespace move requires an ACCESS EXCLUSIVE lock on the index",
            "Review index lock contention, destination CREATE privileges, ownership, free space and partition/temporary-relation behavior. Existing placement and copy work require catalog checks; keep the transaction short.",
          ),
        )
      }
      RenameIndex => {
        if require_lock_timeout || max_lock_timeout_ms is Some(_) {
          timeouts.check(fragment.span, diagnostics, max_lock_timeout_ms)
        }
        diagnostics.push(
          finding(
            "ML110",
            Warning,
            fragment.span,
            "Index rename requires a SHARE UPDATE EXCLUSIVE lock",
            "Review lock contention and constraint naming: a linked UNIQUE, PRIMARY KEY or EXCLUDE constraint is renamed too. Catalog existence and target-name collisions are not checked.",
          ),
        )
      }
      Index(concurrent) | Reindex(concurrent, _) => {
        if command is Reindex(_, true) {
          diagnostics.push(
            finding(
              "ML111",
              Warning,
              fragment.span,
              "REINDEX names a target tablespace and may move index storage",
              "Check tablespace existence, privileges, free space and partition behavior; these catalog and capacity facts are not inferred.",
            ),
          )
        }
        if command is Reindex(false, _) && tx != Idle {
          diagnostics.push(
            finding(
              "ML108",
              Warning,
              fragment.span,
              "Non-concurrent REINDEX in a transaction requires a non-partitioned index",
              "Check the relation kind in the catalog; partitioned indexes cannot be reindexed in a transaction block.",
            ),
          )
        }
        if require_lock_timeout || max_lock_timeout_ms is Some(_) {
          timeouts.check(fragment.span, diagnostics, max_lock_timeout_ms)
        }
        if concurrent {
          if tx == Uncertain {
            complete = false
            diagnostics.push(
              finding(
                "ML102",
                Incomplete,
                fragment.span,
                "Cannot establish transaction context for concurrent index operation",
                "Resolve preceding unsupported SQL and declare the execution mode.",
              ),
            )
          } else if tx != Idle {
            diagnostics.push(
              finding(
                "ML101",
                Error,
                fragment.span,
                "Concurrent index operation cannot run in this transaction context",
                "Dispatch outside a transaction; a multi-statement simple-query message also forms a transaction.",
              ),
            )
          }
        } else {
          diagnostics.push(
            finding(
              "ML100",
              Warning,
              fragment.span,
              "Ordinary index operation can block concurrent access",
              "Check relation kind and lock impact; do not blindly add CONCURRENTLY.",
            ),
          )
        }
      }
      SetTimeout(scoped~, value) =>
        if tx == Uncertain {
          timeouts.taint()
        } else if scoped {
          if tx == Idle {
            diagnostics.push(
              finding(
                "ML200",
                Warning,
                fragment.span,
                "SET LOCAL outside a transaction has no effect",
                "Use a session setting for separately dispatched concurrent index operations.",
              ),
            )
          } else {
            timeouts.scoped = Some(value)
          }
        } else {
          timeouts.session = value
          timeouts.scoped = None
        }
      Savepoint(name) | RollbackTo(name) | Release(name) =>
        if tx != Explicit && tx != External {
          let uncertain = tx == Uncertain
          diagnostics.push(
            finding(
              "ML203",
              if uncertain {
                Incomplete
              } else {
                Error
              },
              fragment.span,
              "Savepoint operation requires an explicit transaction",
              "Declare or begin an explicit transaction; an implicit simple-query block is insufficient.",
            ),
          )
          if uncertain {
            complete = false
          }
          timeouts.taint()
          tx = Uncertain
        } else if command is Savepoint(_) {
          timeouts.mark(name)
        } else if !timeouts.restore(name, release=command is Release(_)) {
          let external = tx == External
          diagnostics.push(
            finding(
              "ML204",
              if external {
                Incomplete
              } else {
                Error
              },
              fragment.span,
              "Savepoint target has not been established by this input",
              "Use an existing savepoint name; external savepoint state is not inferred.",
            ),
          )
          if external {
            complete = false
          }
          timeouts.taint()
          tx = Uncertain
        }
      Unsupported => {
        timeouts.taint()
        complete = false
        tx = Uncertain
        diagnostics.push(
          finding(
            "ML003",
            Incomplete,
            fragment.span,
            "Unsupported or malformed SQL statement",
            "Review manually; downstream transaction context is now unknown.",
          ),
        )
      }
    }
  }
  if tx == Explicit {
    diagnostics.push(
      finding(
        "ML103",
        Warning,
        open_span,
        "Explicit transaction remains open at end of input",
        "Include COMMIT/ROLLBACK or document an enclosing workflow.",
      ),
    )
  }
  { source, statements: scanned.fragments.length(), complete, diagnostics, }
}
