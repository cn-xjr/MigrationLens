///|
fn report_integer(value : Json, location : String) -> Result[Int32, String] {
  match value {
    Number(_, repr=Some(text)) if !text.is_empty() &&
      text.code_units().all(c => c >= 48 && c <= 57) => {
      let n = @string.parse_int(text) catch {
        _ => return Err("\{location} exceeds the nonnegative 32-bit range")
      }
      Ok(n)
    }
    _ =>
      Err(
        "\{location} must be a plain nonnegative decimal 32-bit integer (no fraction or exponent)",
      )
  }
}

///|
/// Decode the version-1 single-report JSON contract without rescanning SQL.
/// Unknown/missing fields, duplicate decoded keys, invalid Unicode, unsupported
/// versions, invalid ranges and inconsistent completion are rejected. Original
/// SQL, diagnostic order and every supported value are preserved.
/// Numeric fields require plain nonnegative decimal integer tokens: fractions,
/// exponents and negative zero are rejected before floating-point rounding.
pub fn Report::parse_json(source : String) -> Result[Report, String] {
  if !valid_unicode(source) {
    return Err("Report JSON contains invalid Unicode")
  }
  let value = @json.parse(
    source,
    reject_duplicate_keys=true,
    max_nesting_depth=16,
    preserve_number_repr=true,
  ) catch {
    e => return Err("Invalid report JSON: \{Repr(e)}")
  }
  guard value is Object(fields) && fields.length() == 5 else {
    return Err(
      "Report must contain exactly format_version, source, statements, complete and diagnostics",
    )
  }
  guard value
    is {
      "format_version": version,
      "source": String(sql),
      "statements": count,
      "complete": completion,
      "diagnostics": Array(items),
      ..
    } else {
    return Err(
      "Expected version-1 single-report fields with string source and diagnostics array",
    )
  }
  guard report_integer(version, "format_version") is Ok(1) else {
    return Err("format_version must be the plain integer 1")
  }
  let complete = match completion {
    True => true
    False => false
    _ => return Err("complete must be boolean")
  }
  let statements = match report_integer(count, "statements") {
    Ok(n) => n
    Err(e) => return Err(e)
  }
  let diagnostics = []
  for i, item in items {
    guard item is Object(fields) && fields.length() == 5 else {
      return Err(
        "diagnostics[\{i}] must contain exactly code, severity, span, message and help",
      )
    }
    guard item
      is {
        "code": String(code),
        "severity": String(level),
        "span": region,
        "message": String(message),
        "help": String(help),
        ..
      } else {
      return Err("diagnostics[\{i}] has missing fields or invalid field types")
    }
    if code.is_empty() || message.is_empty() {
      return Err("diagnostics[\{i}] code and message must not be empty")
    }
    let severity : Severity = match level {
      "Error" => Error
      "Warning" => Warning
      "Incomplete" => Incomplete
      _ =>
        return Err(
          "diagnostics[\{i}].severity must be Error, Warning or Incomplete",
        )
    }
    if complete && severity == Incomplete {
      return Err("complete=true conflicts with an incomplete diagnostic")
    }
    guard region is Object(fields) &&
      fields.length() == 2 &&
      region is { "start": start_json, "end": end_json, .. } else {
      return Err("diagnostics[\{i}].span must contain exactly start and end")
    }
    let start = match
      report_integer(start_json, "diagnostics[\{i}].span.start") {
      Ok(n) => n
      Err(e) => return Err(e)
    }
    let end = match report_integer(end_json, "diagnostics[\{i}].span.end") {
      Ok(n) => n
      Err(e) => return Err(e)
    }
    if end < start || !source_boundary(sql, start) || !source_boundary(sql, end) {
      return Err(
        "diagnostics[\{i}].span is outside the source, reversed or splits a surrogate pair",
      )
    }
    diagnostics.push({ code, severity, span: { start, end, }, message, help, })
  }
  Ok({ source: sql, statements, complete, diagnostics, })
}
