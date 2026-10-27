///|
/// Declared provenance, not authentication. Baselines must still be trusted.
pub struct ReviewOrigin {
  project : String
  tool_version : String
  rules_version : String
  database : String
}

///|
/// Version-2 durable review. One file is represented as a one-entry batch.
/// All execution/policy facts are retained in batch; legacy v1 APIs are unchanged.
pub struct ReviewArchive {
  origin : ReviewOrigin
  batch : BatchReport
}

///|
fn origin_text(text : String) -> Bool {
  !text.is_empty() &&
  text.length() <= 256 &&
  valid_unicode(text) &&
  text.trim().length() == text.length() &&
  !text.code_units().any(c => c < 32 || c == 127)
}

///|
fn ReviewOrigin::to_json(self : ReviewOrigin) -> Json {
  {
    "project": self.project,
    "tool_version": self.tool_version,
    "rules_version": self.rules_version,
    "database": self.database,
  }
}

///|
/// Analyze inputs now; never stamp provenance onto an old unverified report.
/// Project is a stable caller-assigned identifier, 1..256 UTF-16 units.
pub fn ReviewArchive::review(
  project : String,
  inputs : ArrayView[Migration],
  initial_lock_timeout_ms? : Int32,
) -> Result[ReviewArchive, String] {
  if !origin_text(project) {
    return Err(
      "Project must be 1..256 Unicode UTF-16 units without surrounding whitespace or control characters",
    )
  }
  for i, input in inputs {
    if !valid_unicode(input.path) || !valid_unicode(input.source) {
      return Err("Input \{i} path/source contains an unpaired UTF-16 surrogate")
    }
  }
  Ok({
    origin: {
      project,
      tool_version: "0.1.0",
      rules_version: "pg18-review-1",
      database: "postgresql-18",
    },
    batch: review_migrations(inputs, initial_lock_timeout_ms?),
  })
}

///|
pub fn ReviewArchive::exit_code(self : ReviewArchive) -> Int32 {
  self.batch.exit_code()
}

///|
pub fn ReviewArchive::to_json(self : ReviewArchive) -> Json {
  {
    "format_version": 2,
    "origin": self.origin.to_json(),
    "batch": self.batch.to_json(),
  }
}

///|
pub fn ReviewArchive::to_text(self : ReviewArchive) -> String {
  "Project: \{self.origin.project}; tool=\{self.origin.tool_version}; rules=\{self.origin.rules_version}; database=\{self.origin.database}\n" +
  self.batch.to_text()
}

///|
/// Strict restoration without reanalysis. Unknown origins may be viewed but
/// comparison requires a compatible PostgreSQL origin. v1 is never upgraded by
/// guessing: use Report/BatchReport::parse_json to view it, or regenerate it.
pub fn ReviewArchive::parse_json(
  source : String,
) -> Result[ReviewArchive, String] {
  if !valid_unicode(source) {
    return Err("Archive JSON contains invalid Unicode")
  }
  let value = @json.parse(
    source,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
    max_nesting_depth=20,
  ) catch {
    e => return Err("Invalid archive JSON: \{Repr(e)}")
  }
  guard value is Object(root) &&
    root.length() == 3 &&
    value is { "format_version": version, "origin": origin, "batch": saved, .. } else {
    return Err(
      "Expected v2 origin/batch archive; legacy v1 lacks provenance: view with Report/BatchReport::parse_json or regenerate the review",
    )
  }
  guard report_integer(version, "format_version") is Ok(2) else {
    return Err(
      "Archive format_version must be the plain integer 2; legacy reports must be regenerated for checked comparison",
    )
  }
  guard origin is Object(fields) &&
    fields.length() == 4 &&
    origin
    is {
      "project": String(project),
      "tool_version": String(tool_version),
      "rules_version": String(rules_version),
      "database": String(database),
      ..
    } else {
    return Err(
      "Origin requires exactly project, tool_version, rules_version and database strings",
    )
  }
  for text in [project, tool_version, rules_version, database] {
    if !origin_text(text) {
      return Err(
        "Origin strings must be 1..256 Unicode UTF-16 units without surrounding whitespace or control characters",
      )
    }
  }
  let batch = match BatchReport::parse_json(saved.stringify()) {
    Ok(batch) => batch
    Err(e) => return Err("Archive batch: " + e)
  }
  Ok({ origin: { project, tool_version, rules_version, database, }, batch, })
}

///|
pub fn ReviewArchive::to_sarif(self : ReviewArchive) -> Result[Json, String] {
  let log = match self.batch.to_sarif() {
    Ok(log) => log
    Err(e) => return Err(e)
  }
  guard log is Object(root) && root.get("runs") is Some(Array(runs)) else {
    return Err("Unexpected SARIF envelope")
  }
  for run in runs {
    guard run is Object(fields) &&
      fields.get("tool") is Some({ "driver": Object(driver), .. }) else {
      return Err("Unexpected SARIF tool")
    }
    driver["version"] = Json(self.origin.tool_version)
    guard fields.get("properties") is Some(Object(properties)) else {
      return Err("Unexpected SARIF properties")
    }
    properties["migrationLensOrigin"] = self.origin.to_json()
  }
  Ok(log)
}
