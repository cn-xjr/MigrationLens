///|
/// Review a single index statement. Multi-statement context is not covered yet.
pub fn review_sql(source : String, execution~ : Execution) -> Report {
  let scanned = scan(source)
  let diagnostics = scanned.errors.copy()
  let mut complete = diagnostics.is_empty()
  if scanned.fragments.length() > 1 || execution == Unknown {
    complete = false
    diagnostics.push(
      finding(
        "ML010",
        Incomplete,
        { start: 0, end: source.length(), },
        "Execution context is outside this release's coverage",
        "Use one index statement and declare its execution mode.",
      ),
    )
  }
  for fragment in scanned.fragments {
    let parsed = if fragment.words[0] != "CREATE" && fragment.words[0] != "DROP" {
      None
    } else {
      Some(@sql.parse_sql(dialect=@sql.Postgres::{ }, fragment.text)) catch {
        _ => None
      }
    }
    match parsed {
      Some({ stmts: [@sql.CreateIndex(index)], }) =>
        check_index(index.concurrently, execution, fragment.span, diagnostics)
      Some({ stmts: [@sql.DropIndex(index)], }) =>
        check_index(index.concurrently, execution, fragment.span, diagnostics)
      _ => {
        complete = false
        diagnostics.push(
          finding(
            "ML003",
            Incomplete,
            fragment.span,
            "Unsupported or malformed SQL statement",
            "Review this statement manually; it has not been treated as a no-op.",
          ),
        )
      }
    }
  }
  { source, statements: scanned.fragments.length(), complete, diagnostics, }
}

///|
fn check_index(
  concurrent : Bool,
  execution : Execution,
  span : Span,
  diagnostics : Array[Diagnostic],
) -> Unit {
  if concurrent && execution == ExistingTransaction {
    diagnostics.push(
      finding(
        "ML101",
        Error,
        span,
        "Concurrent index operation cannot run in an existing transaction",
        "Run it outside the transaction; confirm the runner's dispatch behavior.",
      ),
    )
  } else if !concurrent {
    diagnostics.push(
      finding(
        "ML100",
        Warning,
        span,
        "Ordinary index operation can block concurrent access",
        "Check relation kind and lock impact; do not blindly add CONCURRENTLY.",
      ),
    )
  }
}
