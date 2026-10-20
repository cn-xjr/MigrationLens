///|
fn classify_refresh(words : ArrayView[String]) -> Command {
  let concurrent = words.get(3) == Some("CONCURRENTLY")
  let start = if concurrent { 4 } else { 3 }
  let end = match relation_name_end(words, start) {
    Some(end) => end
    None => return Unsupported
  }
  let no_data = match words[end:] {
    [] | ["WITH", "DATA"] => false
    ["WITH", "NO", "DATA"] => true
    _ => return Unsupported
  }
  Refresh(concurrent~, no_data~)
}

///|
fn refresh_findings(
  concurrent : Bool,
  no_data : Bool,
  span : Span,
  diagnostics : Array[Diagnostic],
) -> Unit {
  diagnostics.push(
    finding(
      "ML170",
      Warning,
      span,
      if concurrent {
        "Concurrent materialized-view refresh takes EXCLUSIVE locks while allowing ordinary SELECT"
      } else {
        "Materialized-view refresh takes ACCESS EXCLUSIVE locks and blocks readers"
      },
      "Locks are held until transaction end; only one refresh can run per view. Review MAINTAIN privilege, backing-query cost and temporary space. lock_timeout bounds individual lock waits, not refresh duration; result ordering is not preserved by contract.",
    ),
  )
  if concurrent {
    diagnostics.push(
      finding(
        "ML171",
        Warning,
        span,
        "Concurrent refresh requires a populated view and a qualifying UNIQUE index",
        "Verify catalog state: at least one UNIQUE index must cover all rows with plain column keys, without expressions or a WHERE predicate. An unpopulated view cannot be refreshed concurrently. These preconditions are not established by offline SQL review.",
      ),
    )
  }
  if no_data {
    diagnostics.push(
      finding(
        "ML172",
        Warning,
        span,
        "WITH NO DATA leaves the materialized view unscannable",
        "Readers fail until a successful non-concurrent WITH DATA refresh repopulates the view. Plan the outage and follow-up refresh; this statement does not retain the old query results.",
      ),
    )
  }
}
