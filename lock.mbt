///|
priv enum LockMode {
  AccessShare
  RowShare
  RowExclusive
  ShareUpdateExclusive
  Share
  ShareRowExclusive
  Exclusive
  AccessExclusive
}

///|
fn LockMode::name(self : LockMode) -> String {
  match self {
    AccessShare => "ACCESS SHARE"
    RowShare => "ROW SHARE"
    RowExclusive => "ROW EXCLUSIVE"
    ShareUpdateExclusive => "SHARE UPDATE EXCLUSIVE"
    Share => "SHARE"
    ShareRowExclusive => "SHARE ROW EXCLUSIVE"
    Exclusive => "EXCLUSIVE"
    AccessExclusive => "ACCESS EXCLUSIVE"
  }
}

///|
fn LockMode::impact(self : LockMode) -> String {
  match self {
    AccessShare => "conflicts with ACCESS EXCLUSIVE operations"
    RowShare => "conflicts with EXCLUSIVE and ACCESS EXCLUSIVE operations"
    RowExclusive =>
      "allows ordinary concurrent writes but conflicts with SHARE and stronger lock modes"
    ShareUpdateExclusive =>
      "allows ordinary concurrent writes but can conflict with concurrent maintenance and schema operations"
    Share | ShareRowExclusive =>
      "can block ordinary writes while allowing ordinary reads"
    Exclusive =>
      "can block ordinary writes and locking reads while allowing ordinary non-locking reads"
    AccessExclusive => "can block ordinary reads and writes"
  }
}

///|
// Closed grammar: every relation and option is consumed. Catalog-qualified names
// and ONLY (name) are outside the supported subset, not partially interpreted.
fn classify_lock(words : ArrayView[String]) -> Command {
  let mut i = 1
  if words.get(i) == Some("TABLE") {
    i += 1
  }
  let mut count = 0
  while i < words.length() {
    let only = words.get(i) == Some("ONLY")
    if only {
      i += 1
    }
    if i >= words.length() || !index_identifier(words[i]) {
      return Unsupported
    }
    i += 1
    if words.get(i) == Some(".") {
      i += 1
      if i >= words.length() || !index_identifier(words[i]) {
        return Unsupported
      }
      i += 1
    }
    if words.get(i) == Some("*") {
      if only {
        return Unsupported
      }
      i += 1
    }
    count += 1
    if words.get(i) != Some(",") {
      break
    }
    i += 1
    if i == words.length() {
      return Unsupported
    }
  }
  if count == 0 {
    return Unsupported
  }
  let nowait = i < words.length() && words.last() == Some("NOWAIT")
  let end = words.length() - (if nowait { 1 } else { 0 })
  let mode : LockMode = match words[i:end] {
    [] => AccessExclusive
    ["IN", "ACCESS", "SHARE", "MODE"] => AccessShare
    ["IN", "ROW", "SHARE", "MODE"] => RowShare
    ["IN", "ROW", "EXCLUSIVE", "MODE"] => RowExclusive
    ["IN", "SHARE", "UPDATE", "EXCLUSIVE", "MODE"] => ShareUpdateExclusive
    ["IN", "SHARE", "MODE"] => Share
    ["IN", "SHARE", "ROW", "EXCLUSIVE", "MODE"] => ShareRowExclusive
    ["IN", "EXCLUSIVE", "MODE"] => Exclusive
    ["IN", "ACCESS", "EXCLUSIVE", "MODE"] => AccessExclusive
    _ => return Unsupported
  }
  LockTable(mode, nowait)
}
