///|
// A shared, closed ALTER TABLE header. Keep the complete action suffix so an
// unrecognized action cannot inherit the lock level of a recognized neighbor.
fn alter_table_actions(words : ArrayView[String]) -> ArrayView[String]? {
  let mut i = 2
  if words.get(i) == Some("IF") {
    if words.get(i + 1) != Some("EXISTS") {
      return None
    }
    i += 2
  }
  let only = words.get(i) == Some("ONLY")
  if only {
    i += 1
  }
  i = match relation_name_end(words, i) {
    Some(end) => end
    None => return None
  }
  if words.get(i) == Some("*") {
    if only {
      return None
    }
    i += 1
  }
  if i == words.length() {
    None
  } else {
    Some(words[i:])
  }
}

///|
fn classify_alter_table(words : ArrayView[String]) -> Command {
  let actions = match alter_table_actions(words) {
    Some(actions) => actions
    None => return Unsupported
  }
  match actions {
    ["VALIDATE", ..] => classify_validate_constraint(actions)
    ["ADD", ..] => classify_index_constraint(actions)
    _ => Unsupported
  }
}

///|
// Deliberately support the documented order with an explicit DEFERRABLE when
// requesting deferred checks. Repeated/reordered categories remain incomplete.
fn constraint_timing(words : ArrayView[String]) -> Bool? {
  match words {
    []
    | ["NOT", "DEFERRABLE"]
    | ["INITIALLY", "IMMEDIATE"]
    | ["NOT", "DEFERRABLE", "INITIALLY", "IMMEDIATE"] => Some(false)
    ["DEFERRABLE"] | ["DEFERRABLE", "INITIALLY", "IMMEDIATE" | "DEFERRED"] =>
      Some(true)
    _ => None
  }
}
