///|
/// Exact multiset comparison of one caller-assured logical artifact.
pub struct ReportDelta {
  baseline : Report
  current : Report
  introduced : Array[Diagnostic]
  resolved : Array[Diagnostic]
  retained : Int32
}

///|
fn report_snapshot(report : Report) -> Report {
  {
    source: report.source,
    statements: report.statements,
    complete: report.complete,
    diagnostics: report.diagnostics.copy(),
  }
}

///|
fn diagnostic_key(report : Report, diagnostic : Diagnostic) -> String {
  let span = diagnostic.span
  // Ordered JSON tuples avoid delimiter collisions; exact source is retained.
  Json([
    Json(diagnostic.code),
    Json(diagnostic.severity),
    Json(report.source[span.start:span.end].to_owned()),
    Json(diagnostic.message),
    Json(diagnostic.help),
  ]).stringify()
}

///|
/// Compare complete reports from the same artifact, rule version and caller
/// context. Identity is exact code/severity/message/help plus source-span text;
/// only position shifts are ignored. Duplicate multiplicity is preserved.
/// Incomplete or malformed input returns Err, never a passing partial delta.
///
/// ```mbt check
/// test {
///   let before = @migration_lens.review_sql(
///     "DROP INDEX a;",
///     execution=SeparateStatements,
///   )
///   let after = @migration_lens.review_sql(
///     "-- shifted\nDROP INDEX a;",
///     execution=SeparateStatements,
///   )
///   let delta = @migration_lens.compare_reports(before, after).unwrap()
///   assert_eq(delta.retained, 1)
///   assert_eq(delta.exit_code(), 0)
/// }
/// ```
pub fn compare_reports(
  baseline : Report,
  current : Report,
) -> Result[ReportDelta, String] {
  for (report, label) in [(baseline, "Baseline"), (current, "Current")] {
    match validate_report(report, label) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    if !report.complete {
      return Err(
        "\{label} analysis is incomplete; resolve coverage before applying a baseline",
      )
    }
  }
  let baseline = report_snapshot(baseline)
  let current = report_snapshot(current)
  let remaining_before : Map[String, Int32] = Map([])
  let remaining_after : Map[String, Int32] = Map([])
  for d in baseline.diagnostics {
    let key = diagnostic_key(baseline, d)
    remaining_before[key] = remaining_before.get(key).unwrap_or(0) + 1
  }
  for d in current.diagnostics {
    let key = diagnostic_key(current, d)
    remaining_after[key] = remaining_after.get(key).unwrap_or(0) + 1
  }
  let introduced = []
  for d in current.diagnostics {
    let key = diagnostic_key(current, d)
    let count = remaining_before.get(key).unwrap_or(0)
    if count == 0 {
      introduced.push(d)
    } else {
      remaining_before[key] = count - 1
    }
  }
  let resolved = []
  for d in baseline.diagnostics {
    let key = diagnostic_key(baseline, d)
    let count = remaining_after.get(key).unwrap_or(0)
    if count == 0 {
      resolved.push(d)
    } else {
      remaining_after[key] = count - 1
    }
  }
  Ok({
    baseline,
    current,
    introduced,
    resolved,
    retained: current.diagnostics.length() - introduced.length(),
  })
}

///|
/// Baseline gate: 1 for introduced findings, otherwise 0. Retained errors remain
/// visible in current; this result is not an absolute migration safety check.
pub fn ReportDelta::exit_code(self : ReportDelta) -> Int32 {
  if self.introduced.is_empty() {
    0
  } else {
    1
  }
}

///|
pub fn ReportDelta::to_json(self : ReportDelta) -> Json {
  {
    "format_version": 1,
    "baseline": self.baseline.to_json(),
    "current": self.current.to_json(),
    "introduced": Json(self.introduced),
    "resolved": Json(self.resolved),
    "retained": self.retained,
    "exit_code": self.exit_code(),
  }
}

///|
pub fn ReportDelta::to_text(self : ReportDelta) -> String {
  let added : Report = {
    source: self.current.source,
    statements: self.current.statements,
    complete: true,
    diagnostics: self.introduced,
  }
  let removed : Report = {
    source: self.baseline.source,
    statements: self.baseline.statements,
    complete: true,
    diagnostics: self.resolved,
  }
  "MigrationLens delta: \{self.introduced.length()} introduced; \{self.resolved.length()} resolved; \{self.retained} retained; exit=\{self.exit_code()}\n" +
  "Introduced (current source):\n" +
  added.to_text() +
  "Resolved (baseline source):\n" +
  removed.to_text()
}
