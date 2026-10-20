///|
fn identifier_list_end(
  words : ArrayView[String],
  start : Int32,
) -> (Int32, Int32)? {
  if words.get(start) != Some("(") {
    return None
  }
  let mut i = start + 1
  let mut count = 0
  while i < words.length() {
    if !index_identifier(words[i]) {
      return None
    }
    count += 1
    i += 1
    match words.get(i) {
      Some(")") => return Some((i + 1, count))
      Some(",") => i += 1
      _ => return None
    }
  }
  None
}

///|
// Return the next token and whether the referential action changes child rows.
// Column subsets after SET NULL/DEFAULT are intentionally outside this grammar.
fn foreign_key_action(
  words : ArrayView[String],
  start : Int32,
) -> (Int32, Bool)? {
  match words[start:] {
    ["CASCADE", ..] => Some((start + 1, true))
    ["RESTRICT", ..] => Some((start + 1, false))
    ["NO", "ACTION", ..] => Some((start + 2, false))
    ["SET", "NULL" | "DEFAULT", ..] => Some((start + 2, true))
    _ => None
  }
}

///|
fn classify_foreign_key(words : ArrayView[String]) -> Command {
  let (start, columns) = match identifier_list_end(words, 2) {
    Some(parsed) => parsed
    None => return Unsupported
  }
  let mut i = start
  if words.get(i) != Some("REFERENCES") {
    return Unsupported
  }
  i = match relation_name_end(words, i + 1) {
    Some(end) => end
    None => return Unsupported
  }
  if words.get(i) == Some("(") {
    match identifier_list_end(words, i) {
      Some((end, referenced_columns)) if referenced_columns == columns =>
        i = end
      _ => return Unsupported
    }
  }
  if words.get(i) == Some("MATCH") {
    match words.get(i + 1) {
      Some("FULL" | "SIMPLE") => i += 2
      _ => return Unsupported
    }
  }
  let mut seen_delete = false
  let mut seen_update = false
  let mut mutates_rows = false
  while words.get(i) == Some("ON") {
    match words.get(i + 1) {
      Some("DELETE") if !seen_delete => seen_delete = true
      Some("UPDATE") if !seen_update => seen_update = true
      _ => return Unsupported
    }
    match foreign_key_action(words, i + 2) {
      Some((end, changes)) => {
        i = end
        mutates_rows = mutates_rows || changes
      }
      None => return Unsupported
    }
  }
  let not_valid = words.length() >= i + 2 &&
    words.get(words.length() - 2) == Some("NOT") &&
    words.get(words.length() - 1) == Some("VALID")
  let end = if not_valid { words.length() - 2 } else { words.length() }
  match constraint_timing(words[i:end]) {
    Some(deferrable) => AddForeignKey(not_valid~, deferrable~, mutates_rows~)
    None => Unsupported
  }
}

///|
fn foreign_key_findings(
  not_valid : Bool,
  deferrable : Bool,
  mutates_rows : Bool,
  span : Span,
  diagnostics : Array[Diagnostic],
) -> Unit {
  diagnostics.push(
    finding(
      "ML210",
      Warning,
      span,
      "Adding a foreign key takes SHARE ROW EXCLUSIVE locks on both tables",
      "These locks conflict with ordinary writes and persist until transaction end, even with NOT VALID. Budget waits on referencing and referenced relations; lock_timeout does not bound the entire operation.",
    ),
  )
  diagnostics.push(
    if not_valid {
      finding(
        "ML211",
        Warning,
        span,
        "NOT VALID skips the historical foreign-key scan but enforces subsequent writes",
        "Commit installation separately, repair pre-existing violations, then run VALIDATE CONSTRAINT. This review does not establish that historical rows satisfy the foreign key; NOT VALID is not disabled enforcement.",
      )
    } else {
      finding(
        "ML212",
        Warning,
        span,
        "Adding a validated foreign key may scan historical rows while writes are blocked",
        "For large existing tables, consider a separately committed NOT VALID installation followed by VALIDATE CONSTRAINT after data repair. This reviewer does not rewrite SQL or infer whether PostgreSQL can skip the scan.",
      )
    },
  )
  diagnostics.push(
    finding(
      "ML214",
      Warning,
      span,
      "Foreign-key eligibility and data compatibility require catalog checks",
      "Check referenced key eligibility, matching column types, REFERENCES privileges, null/MATCH semantics, partition restrictions and referencing-column indexes. " +
      (if deferrable {
        "DEFERRABLE changes check timing; referential actions still execute with the data-changing command. "
      } else {
        ""
      }) +
      "Constraint existence, enforcement success and operation cost are not proved offline.",
    ),
  )
  if mutates_rows {
    diagnostics.push(
      finding(
        "ML213",
        Warning,
        span,
        "Foreign-key referential actions can modify or delete referencing rows",
        "Review each ON DELETE/UPDATE CASCADE or SET NULL/DEFAULT action in the retained SQL, including fan-out, child indexes and NOT NULL/default compatibility. Deferrable checks do not defer these actions.",
      ),
    )
  }
}
