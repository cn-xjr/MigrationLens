///|
priv struct Entry {
  path : String
  execution : @lens.Execution
  initial_transaction : Bool
  require_lock_timeout : Bool
  maximum : Int32?
}

///|
priv struct Manifest {
  entries : Array[Entry]
  initial_lock_timeout_ms : Int32?
}

///|
fn parse_entries(source : String) -> Result[Manifest, String] {
  if source.length() > 1000000 {
    return Err("Manifest exceeds 1,000,000 UTF-16 units")
  }
  let value = @json.parse(
    source,
    reject_duplicate_keys=true,
    max_nesting_depth=16,
  ) catch {
    e =>
      return Err(
        "Invalid JSON manifest (duplicate keys are rejected): \{Repr(e)}",
      )
  }
  guard value is Object(root) else { return Err("Manifest must be an object") }
  for key in root.keys() {
    if !["format_version", "migrations", "initial_lock_timeout_ms"].contains(
        key,
      ) {
      return Err(
        "Manifest supports only format_version, migrations and optional initial_lock_timeout_ms",
      )
    }
  }
  guard value is { "format_version": 1, "migrations": Array(items), .. } else {
    return Err("Expected format_version=1 and a migrations array")
  }
  if items.is_empty() || items.length() > 1000 {
    return Err("Manifest requires 1 through 1000 migration entries")
  }
  let initial_lock_timeout_ms = match root.get("initial_lock_timeout_ms") {
    None => None
    Some(Number(n, ..)) if n >= 0 &&
      n <= 2147483647.0 &&
      n == n.to_int().to_double() => Some(n.to_int())
    _ =>
      return Err(
        "initial_lock_timeout_ms must be an integer from 0 through 2147483647",
      )
  }
  let entries = []
  for i, item in items {
    guard item is Object(fields) else {
      return Err("Entry \{i}: expected an object")
    }
    for key in fields.keys() {
      if ![
          "path", "execution", "initial_transaction", "require_lock_timeout", "max_lock_timeout_ms",
        ].contains(key) {
        return Err(
          "Entry \{i}: unknown fields; allowed path, execution, initial_transaction, require_lock_timeout, max_lock_timeout_ms",
        )
      }
    }
    guard item is { "path": String(raw_path), "execution": String(mode), .. } else {
      return Err("Entry \{i}: path and execution strings are required")
    }
    let path = raw_path.replace(old="\\", new="/")
    if path.is_empty() ||
      path.has_prefix("/") ||
      path.contains(":") ||
      path.code_units().any(c => c < 32 || c == 127) {
      return Err(
        "Entry \{i}: use a repository-relative file path without control characters, drive or scheme",
      )
    }
    for part in path.split("/") {
      if part.is_empty() || part == "." || part == ".." {
        return Err("Entry \{i}: empty/dot/parent path components are forbidden")
      }
    }
    let execution : @lens.Execution = match mode {
      "separate" => SeparateStatements
      "simple" => SimpleQuery
      "transaction" => ExistingTransaction
      "unknown" => Unknown
      _ =>
        return Err(
          "Entry \{i}: execution must be separate, simple, transaction or unknown",
        )
    }
    let initial_transaction = match fields.get("initial_transaction") {
      None => false
      Some(True) => true
      Some(False) => false
      _ => return Err("Entry \{i}: initial_transaction must be boolean")
    }
    let require_lock_timeout = match fields.get("require_lock_timeout") {
      None => false
      Some(True) => true
      Some(False) => false
      _ => return Err("Entry \{i}: require_lock_timeout must be boolean")
    }
    let maximum = match fields.get("max_lock_timeout_ms") {
      None => None
      Some(Number(n, ..)) if n >= 1 &&
        n <= 2147483647.0 &&
        n == n.to_int().to_double() => Some(n.to_int())
      _ =>
        return Err(
          "Entry \{i}: max_lock_timeout_ms must be an integer from 1 through 2147483647",
        )
    }
    entries.push({
      path,
      execution,
      initial_transaction,
      require_lock_timeout,
      maximum,
    })
  }
  Ok({ entries, initial_lock_timeout_ms, })
}
