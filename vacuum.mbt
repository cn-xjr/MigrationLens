///|
fn classify_vacuum(words : ArrayView[String]) -> Command {
  let (start, options) = match
    maintenance_options(
      words,
      [
        "FULL", "FREEZE", "VERBOSE", "ANALYZE", "SKIP_LOCKED", "TRUNCATE", "INDEX_CLEANUP",
      ][:],
    ) {
    Some(parsed) => parsed
    None => return Unsupported
  }
  let mut start = start
  if start == 1 {
    // The documented legacy order is FULL, FREEZE, VERBOSE, ANALYZE.
    for flag in ["FULL", "FREEZE", "VERBOSE", "ANALYZE"] {
      if words.get(start) == Some(flag) {
        options[flag] = true
        start += 1
      }
    }
  }
  match
    maintenance_targets(
      words[start:],
      allow_columns=options.get("ANALYZE").unwrap_or(false),
    ) {
    Some(database_wide) =>
      Vacuum(
        full=options.get("FULL").unwrap_or(false),
        skip_locked=options.get("SKIP_LOCKED").unwrap_or(false),
        truncate=options.get("TRUNCATE").unwrap_or(true),
        cleanup_off=options.get("INDEX_CLEANUP") == Some(false),
        database_wide~,
      )
    None => Unsupported
  }
}
