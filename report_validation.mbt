///|
fn validate_report(report : Report, label : String) -> Result[Unit, String] {
  if !valid_unicode(report.source) {
    return Err("\{label} source contains an unpaired UTF-16 surrogate")
  }
  if report.statements < 0 {
    return Err("\{label} report has a negative statement count")
  }
  for i, d in report.diagnostics {
    if report.complete && d.severity == Incomplete {
      return Err("\{label} complete report contains an incomplete diagnostic")
    }
    if d.code.is_empty() ||
      d.message.is_empty() ||
      !valid_unicode(d.code) ||
      !valid_unicode(d.message) ||
      !valid_unicode(d.help) {
      return Err(
        "\{label} diagnostic \{i} has empty code/message or invalid Unicode",
      )
    }
    if d.span.end < d.span.start ||
      !source_boundary(report.source, d.span.start) ||
      !source_boundary(report.source, d.span.end) {
      return Err("\{label} diagnostic \{i} has an invalid source span")
    }
  }
  Ok(())
}
