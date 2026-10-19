///|
priv enum Command {
  Index(Bool)
  Reindex(Bool)
  InvalidIndex(String)
  Begin
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
    ["BEGIN"]
    | ["BEGIN", "WORK"]
    | ["BEGIN", "TRANSACTION"]
    | ["START", "TRANSACTION"] => Begin
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
    ["REINDEX", "INDEX", .. rest] => {
      let (concurrent, name) = match rest {
        ["CONCURRENTLY", .. name] => (true, name)
        _ => (false, rest)
      }
      match name {
        [index] if index_identifier(index) => Reindex(concurrent)
        [schema, ".", index] if index_identifier(schema) &&
          index_identifier(index) => Reindex(concurrent)
        _ => Unsupported
      }
    }
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
/// Analyze PostgreSQL 18 index statements and transaction control. The caller
/// must describe dispatch; comments never override the explicit execution mode.
/// A positive max_lock_timeout_ms also enables timeout checking. Invalid limits
/// yield ML011 and an incomplete report without analyzing statements.
pub fn review_sql(
  source : String,
  execution~ : Execution,
  initial_transaction~ : Bool = false,
  require_lock_timeout~ : Bool = false,
  max_lock_timeout_ms? : Int32,
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
  let timeouts = TimeoutState::new()
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
      Begin =>
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
      Index(concurrent) | Reindex(concurrent) => {
        if command is Reindex(false) && tx != Idle {
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
