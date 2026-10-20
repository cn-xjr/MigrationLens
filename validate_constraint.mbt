///|
// All actions must be validations: a mixed ALTER TABLE can require a stronger
// lock, so never discard the remainder or infer its semantics from one action.
fn classify_validate_constraint(words : ArrayView[String]) -> Command {
  let mut i = 2
  if words.get(i) == Some("IF") {
    if words.get(i + 1) != Some("EXISTS") {
      return Unsupported
    }
    i += 2
  }
  let only = words.get(i) == Some("ONLY")
  if only {
    i += 1
  }
  i = match relation_name_end(words, i) {
    Some(end) => end
    None => return Unsupported
  }
  if words.get(i) == Some("*") {
    if only {
      return Unsupported
    }
    i += 1
  }
  while i < words.length() {
    if words.get(i) != Some("VALIDATE") ||
      words.get(i + 1) != Some("CONSTRAINT") {
      return Unsupported
    }
    if i + 2 >= words.length() || !index_identifier(words[i + 2]) {
      return Unsupported
    }
    i += 3
    if i == words.length() {
      return ValidateConstraint
    }
    if words.get(i) != Some(",") {
      return Unsupported
    }
    i += 1
  }
  Unsupported
}

///|
fn constraint_validation_findings(
  span : Span,
  diagnostics : Array[Diagnostic],
) -> Unit {
  diagnostics.push(
    finding(
      "ML180",
      Warning,
      span,
      "Constraint validation may scan existing rows under SHARE UPDATE EXCLUSIVE locks",
      "Plan scan work and maintenance/schema contention; ordinary updates can continue. Locks persist until transaction end. lock_timeout bounds individual lock waits, not the scan duration. Keep ADD CONSTRAINT and validation in separately reviewed phases.",
    ),
  )
  diagnostics.push(
    finding(
      "ML181",
      Warning,
      span,
      "Constraint validation requires catalog and existing-data checks",
      "Verify the named FOREIGN KEY, CHECK or NOT NULL constraint exists and is enforced; already-valid constraints need no validation work. Foreign keys also require ROW SHARE locks on referenced tables. Review violations, privileges, ONLY/descendant scope and partition behavior; offline review does not prove data satisfies the constraint.",
    ),
  )
}
