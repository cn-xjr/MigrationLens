///|
// Consume exactly one optional-schema relation name, never a catalog prefix.
fn relation_name_end(words : ArrayView[String], start : Int32) -> Int32? {
  if start >= words.length() || !index_identifier(words[start]) {
    return None
  }
  let mut end = start + 1
  if words.get(end) == Some(".") {
    if end + 1 >= words.length() || !index_identifier(words[end + 1]) {
      return None
    }
    end += 2
  }
  Some(end)
}

///|
fn classify_cluster(words : ArrayView[String]) -> Command {
  let (start, _) = match maintenance_options(words, ["VERBOSE"][:]) {
    Some(parsed) => parsed
    None => return Unsupported
  }
  let start = if start == 1 && words.get(1) == Some("VERBOSE") {
    2
  } else {
    start
  }
  if start == words.length() {
    return Cluster(database_wide=true)
  }
  let end = match relation_name_end(words, start) {
    Some(end) => end
    None => return Unsupported
  }
  match words[end:] {
    [] => Cluster(database_wide=false)
    ["USING", index] if index_identifier(index) => Cluster(database_wide=false)
    _ => Unsupported
  }
}

///|
fn cluster_findings(
  database_wide : Bool,
  span : Span,
  diagnostics : Array[Diagnostic],
) -> Unit {
  diagnostics.push(
    finding(
      "ML160",
      Warning,
      span,
      "CLUSTER physically reorders tables under ACCESS EXCLUSIVE locks",
      "Budget blocked reads/writes, table/index rewrite space and duration; run ANALYZE afterwards. Ordering is not maintained by later writes. lock_timeout bounds individual lock waits, not total rewrite time.",
    ),
  )
  diagnostics.push(
    if database_wide {
      finding(
        "ML161",
        Warning,
        span,
        "CLUSTER without a table visits previously clustered tables in the database",
        "Name the intended table to bound work. Actual targets depend on remembered clustering indexes, privileges and catalog state.",
      )
    } else {
      finding(
        "ML163",
        Warning,
        span,
        "Targeted CLUSTER requires catalog checks for index and partition behavior",
        "Check MAINTAIN privilege and a suitable existing index; an omitted USING needs a remembered clustering index. Partitioned targets require USING and cannot run in transaction blocks. This offline review does not establish relation kind or index suitability.",
      )
    },
  )
}
