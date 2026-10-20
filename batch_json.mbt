///|
fn report_signed_integer(
  value : Json,
  location : String,
) -> Result[Int32, String] {
  guard value is Number(_, repr=Some(text)) else {
    return Err("\{location} must be a plain signed 32-bit decimal integer")
  }
  let digits = if text.has_prefix("-") { text[1:].to_owned() } else { text }
  if digits.is_empty() ||
    !digits.code_units().all(c => c >= 48 && c <= 57) ||
    text == "-0" {
    return Err(
      "\{location} must use decimal digits, without fractions, exponents or negative zero",
    )
  }
  let n = @string.parse_int(text) catch {
    _ => return Err("\{location} exceeds the signed 32-bit range")
  }
  Ok(n)
}

///|
/// Restore a version-1 batch without reading SQL files or rerunning analysis.
/// Unknown fields, duplicate keys and inconsistent contexts/exit codes are
/// rejected. Invalid-policy reports are retained with their configuration error.
///
/// ```mbt check
/// test {
///   let original = @migration_lens.review_migrations(
///     [][:],
///     initial_lock_timeout_ms=100,
///   )
///   let loaded = @migration_lens.BatchReport::parse_json(
///     original.to_json().stringify(),
///   ).unwrap()
///   assert_eq(loaded.to_json(), original.to_json())
/// }
/// ```
pub fn BatchReport::parse_json(source : String) -> Result[BatchReport, String] {
  if !valid_unicode(source) {
    return Err("Batch JSON contains invalid Unicode")
  }
  let value = @json.parse(
    source,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
    max_nesting_depth=16,
  ) catch {
    e => return Err("Invalid batch JSON: \{Repr(e)}")
  }
  guard value is Object(root) &&
    value
    is {
      "format_version": version,
      "exit_code": exit,
      "files": Array(items),
      ..
    } else {
    return Err("Batch requires format_version, exit_code and files")
  }
  guard report_integer(version, "format_version") is Ok(1) else {
    return Err("Batch format_version must be the plain integer 1")
  }
  let exit = match report_integer(exit, "exit_code") {
    Ok(n) if n <= 2 => n
    _ => return Err("Batch exit_code must be 0, 1 or 2")
  }
  let initial_lock_timeout_ms = match root.get("initial_lock_timeout_ms") {
    None => None
    Some(value) =>
      match report_signed_integer(value, "initial_lock_timeout_ms") {
        Ok(n) => Some(n)
        Err(e) => return Err(e)
      }
  }
  let files = []
  for i, item in items {
    guard item is Object(fields) &&
      fields.length() == 3 &&
      item is { "path": String(path), "context": context, "report": saved, .. } else {
      return Err("files[\{i}] must contain exactly path, context and report")
    }
    guard context
      is {
        "execution": String(mode),
        "initial_transaction": initial,
        "require_lock_timeout": required,
        "max_lock_timeout_ms": maximum,
        ..
      } else {
      return Err(
        "files[\{i}].context requires execution and every policy field",
      )
    }
    let execution : Execution = match mode {
      "SeparateStatements" => SeparateStatements
      "SimpleQuery" => SimpleQuery
      "ExistingTransaction" => ExistingTransaction
      "Unknown" => Unknown
      _ => return Err("files[\{i}].context.execution is unsupported")
    }
    let initial_transaction = match initial {
      True => true
      False => false
      _ => return Err("files[\{i}].context.initial_transaction must be boolean")
    }
    let require_lock_timeout = match required {
      True => true
      False => false
      _ =>
        return Err("files[\{i}].context.require_lock_timeout must be boolean")
    }
    let max_lock_timeout_ms = match maximum {
      Null => None
      [value] =>
        match
          report_signed_integer(
            value,
            "files[\{i}].context.max_lock_timeout_ms[0]",
          ) {
          Ok(n) => Some(n)
          Err(e) => return Err(e)
        }
      _ =>
        return Err(
          "files[\{i}].context.max_lock_timeout_ms must be null or a one-integer array",
        )
    }
    let report = match Report::parse_json(saved.stringify()) {
      Ok(r) => r
      Err(e) => return Err("files[\{i}].report: \{e}")
    }
    let migration : Migration = {
      path,
      source: report.source,
      execution,
      initial_transaction,
      require_lock_timeout,
      max_lock_timeout_ms,
    }
    if report.complete &&
      (
        execution == Unknown ||
        (max_lock_timeout_ms is Some(n) && n <= 0) ||
        (initial_lock_timeout_ms is Some(n) && n < 0)
      ) {
      return Err(
        "files[\{i}] has a complete report despite unknown execution or an invalid policy",
      )
    }
    if context != migration_context(migration, initial_lock_timeout_ms?) {
      return Err(
        "files[\{i}].context contains unknown/missing fields or inconsistent path/initial timeout",
      )
    }
    files.push({ migration, report, })
  }
  let batch : BatchReport = { files, initial_lock_timeout_ms, }
  if batch.exit_code() != exit || batch.to_json() != value {
    return Err(
      "Batch has unknown/missing fields, an inconsistent exit_code or an invalid configuration_error",
    )
  }
  Ok(batch)
}
