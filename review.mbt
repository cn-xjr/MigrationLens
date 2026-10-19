///|
priv enum Command {
  Index(Bool)
  Begin
  Commit
  Rollback
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
    ["BEGIN"]
    | ["BEGIN", "WORK"]
    | ["BEGIN", "TRANSACTION"]
    | ["START", "TRANSACTION"] => Begin
    ["COMMIT"] | ["COMMIT", "WORK"] | ["COMMIT", "TRANSACTION"] => Commit
    ["ROLLBACK"] | ["ROLLBACK", "WORK"] | ["ROLLBACK", "TRANSACTION"] =>
      Rollback
    ["CREATE", ..] | ["DROP", ..] => {
      let parsed = @sql.parse_sql(dialect=@sql.Postgres::{ }, fragment.text) catch {
        _ => return Unsupported
      }
      match parsed.stmts[:] {
        [@sql.CreateIndex(index)] => Index(index.concurrently)
        [@sql.DropIndex(index)] if index.table_name is None =>
          Index(index.concurrently)
        _ => Unsupported
      }
    }
    _ => Unsupported
  }
}

///|
/// Analyze PostgreSQL 18 index statements and transaction control. The caller
/// must describe dispatch; comments never override the explicit execution mode.
pub fn review_sql(source : String, execution~ : Execution) -> Report {
  let scanned = scan(source)
  let diagnostics = scanned.errors.copy()
  let mut complete = diagnostics.is_empty()
  let mut tx : Transaction = match execution {
    ExistingTransaction => External
    Unknown => Uncertain
    _ => Idle
  }
  let batch = execution == SimpleQuery && scanned.fragments.length() > 1
  let mut open_span : Span = { start: 0, end: 0, }
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
      tx = Implicit
    }
    match classify(fragment) {
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
          tx = Explicit
          open_span = fragment.span
        }
      Commit | Rollback => {
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
          tx = Idle
        }
      }
      Index(concurrent) =>
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
      Unsupported => {
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
