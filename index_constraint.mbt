///|
fn classify_index_constraint(words : ArrayView[String]) -> Command {
  let mut i = 0
  let primary_key = match words.get(i) {
    Some("UNIQUE") => {
      i += 1
      false
    }
    Some("PRIMARY") if words.get(i + 1) == Some("KEY") => {
      i += 2
      true
    }
    _ => return Unsupported
  }
  if words.get(i) != Some("USING") ||
    words.get(i + 1) != Some("INDEX") ||
    i + 2 >= words.length() ||
    !index_identifier(words[i + 2]) {
    return Unsupported
  }
  match constraint_timing(words[i + 3:]) {
    Some(deferrable) => AddIndexConstraint(primary_key~, deferrable~)
    None => Unsupported
  }
}

///|
fn index_constraint_findings(
  primary_key : Bool,
  deferrable : Bool,
  span : Span,
  diagnostics : Array[Diagnostic],
) -> Unit {
  diagnostics.push(
    finding(
      "ML190",
      Warning,
      span,
      "Attaching an index as a constraint requires ACCESS EXCLUSIVE on the table",
      "Concurrent index creation does not remove the final table-lock requirement. Budget acquisition waits and hold the transaction briefly; lock_timeout is not a total-operation time budget.",
    ),
  )
  diagnostics.push(
    finding(
      "ML191",
      Warning,
      span,
      "Index-backed constraints require catalog checks and take ownership of the index",
      "Verify an eligible existing UNIQUE b-tree index with default ordering, no expressions or predicate, and a non-partitioned target. A named constraint renames the index; dropping the constraint also drops its owned index. Existence, validity, ownership and name collisions are not inferred.",
    ),
  )
  if primary_key {
    diagnostics.push(
      finding(
        "ML192",
        Warning,
        span,
        "PRIMARY KEY attachment can require NOT NULL checks and table scans",
        "If indexed columns are not already marked NOT NULL, PostgreSQL attempts SET NOT NULL. Check existing nulls and scan-elision prerequisites before scheduling the ACCESS EXCLUSIVE phase; index uniqueness alone does not establish nullability.",
      ),
    )
  }
  if deferrable {
    diagnostics.push(
      finding(
        "ML193",
        Warning,
        span,
        "DEFERRABLE changes when the attached constraint can be checked",
        "Review INITIALLY IMMEDIATE/DEFERRED behavior and downstream expectations. This review does not model SET CONSTRAINTS or prove that a transaction's final data satisfies the constraint.",
      ),
    )
  }
}
