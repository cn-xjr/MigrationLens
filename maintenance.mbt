///|
// Return the token following a complete option list and each explicit setting.
// Accept declared boolean names or INDEX_CLEANUP's AUTO/ON/OFF. For that option,
// true means "not explicitly OFF", never proof that cleanup will occur.
fn maintenance_options(
  words : ArrayView[String],
  allowed : ArrayView[String],
) -> (Int32, Map[String, Bool])? {
  let values : Map[String, Bool] = Map([])
  if words.get(1) != Some("(") {
    return Some((1, values))
  }
  let mut i = 2
  while i < words.length() {
    let option = words[i]
    if !allowed.contains(option) || values.contains(option) {
      return None
    }
    i += 1
    let enabled = if option == "INDEX_CLEANUP" {
      match words.get(i) {
        Some("AUTO" | "ON") => {
          i += 1
          true
        }
        Some("OFF") => {
          i += 1
          false
        }
        _ => return None
      }
    } else {
      match words.get(i) {
        Some("TRUE" | "ON" | "1") => {
          i += 1
          true
        }
        Some("FALSE" | "OFF" | "0") => {
          i += 1
          false
        }
        Some("," | ")") => true
        _ => return None
      }
    }
    values[option] = enabled
    match words.get(i) {
      Some(")") => return Some((i + 1, values))
      Some(",") => i += 1
      _ => return None
    }
  }
  None
}

///|
// Each target is [ONLY] [schema.]name [*] [(column, ...)]; no expressions,
// aliases or catalog-qualified names are reduced to a supported target.
// Some(true) means an intentionally empty, database-wide target list.
fn maintenance_targets(
  words : ArrayView[String],
  allow_columns~ : Bool,
) -> Bool? {
  if words.is_empty() {
    return Some(true)
  }
  let mut i = 0
  while i < words.length() {
    let only = words.get(i) == Some("ONLY")
    if only {
      i += 1
    }
    if i >= words.length() || !index_identifier(words[i]) {
      return None
    }
    i += 1
    if words.get(i) == Some(".") {
      i += 1
      if i >= words.length() || !index_identifier(words[i]) {
        return None
      }
      i += 1
    }
    if words.get(i) == Some("*") {
      if only {
        return None
      }
      i += 1
    }
    if words.get(i) == Some("(") {
      if !allow_columns {
        return None
      }
      i += 1
      while i < words.length() {
        if !index_identifier(words[i]) {
          return None
        }
        i += 1
        if words.get(i) == Some(")") {
          i += 1
          break
        }
        if words.get(i) != Some(",") {
          return None
        }
        i += 1
      }
      // The last consumed token must close a nonempty column list.
      if words.get(i - 1) != Some(")") {
        return None
      }
    }
    if i == words.length() {
      return Some(false)
    }
    if words.get(i) != Some(",") {
      return None
    }
    i += 1
  }
  None
}

///|
fn classify_analyze(words : ArrayView[String]) -> Command {
  let (start, options) = match
    maintenance_options(words, ["VERBOSE", "SKIP_LOCKED"][:]) {
    Some(parsed) => parsed
    None => return Unsupported
  }
  let start = if start == 1 && words.get(1) == Some("VERBOSE") {
    2
  } else {
    start
  }
  match maintenance_targets(words[start:], allow_columns=true) {
    Some(database_wide) =>
      Analyze(
        skip_locked=options.get("SKIP_LOCKED").unwrap_or(false),
        database_wide~,
      )
    None => Unsupported
  }
}
