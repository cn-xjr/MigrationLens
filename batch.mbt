///|
/// One independent input. No transaction or setting state flows between inputs.
pub(all) struct Migration {
  path : String
  source : String
  execution : Execution
  initial_transaction : Bool
  require_lock_timeout : Bool
  max_lock_timeout_ms : Int32?
}

///|
pub fn Migration::new(
  path : String,
  source : String,
  execution~ : Execution,
  initial_transaction~ : Bool = false,
  require_lock_timeout~ : Bool = false,
  max_lock_timeout_ms? : Int32,
) -> Migration {
  {
    path,
    source,
    execution,
    initial_transaction,
    require_lock_timeout,
    max_lock_timeout_ms,
  }
}

///|
pub struct FileReport {
  migration : Migration
  report : Report
}

///|
/// Input order and duplicate path labels are retained. Each file has its own run.
pub struct BatchReport {
  files : Array[FileReport]
  initial_lock_timeout_ms : Int32?
}

///|
/// Review every input even if earlier inputs are incomplete or have findings.
/// An optional initial_lock_timeout_ms starts every independent review with the
/// same caller-assured session value; it never flows from an earlier input.
pub fn review_migrations(
  inputs : ArrayView[Migration],
  initial_lock_timeout_ms? : Int32,
) -> BatchReport {
  let files = []
  for input in inputs {
    files.push({
      migration: input,
      report: review_sql(
        input.source,
        execution=input.execution,
        initial_transaction=input.initial_transaction,
        require_lock_timeout=input.require_lock_timeout,
        max_lock_timeout_ms?=input.max_lock_timeout_ms,
        initial_lock_timeout_ms?,
      ),
    })
  }
  { files, initial_lock_timeout_ms, }
}

///|
/// Highest per-file exit code: incomplete (2) wins over findings (1) and clean (0).
pub fn BatchReport::exit_code(self : BatchReport) -> Int32 {
  if self.initial_lock_timeout_ms is Some(value) && value < 0 {
    return 2
  }
  let mut code = 0
  for file in self.files {
    if file.report.exit_code() > code {
      code = file.report.exit_code()
    }
  }
  code
}

///|
pub fn BatchReport::to_json(self : BatchReport) -> Json {
  let files : Array[Json] = []
  for file in self.files {
    files.push({
      "path": file.migration.path,
      "context": migration_context(
        file.migration,
        initial_lock_timeout_ms?=self.initial_lock_timeout_ms,
      ),
      "report": file.report.to_json(),
    })
  }
  let data : Json = {
    "format_version": 1,
    "exit_code": self.exit_code(),
    "files": Json(files),
  }
  if self.initial_lock_timeout_ms is Some(value) && data is Object(fields) {
    fields["initial_lock_timeout_ms"] = Json(value)
    if value < 0 {
      fields["configuration_error"] = Json(
        "initial_lock_timeout_ms must be nonnegative",
      )
    }
  }
  data
}

///|
pub fn BatchReport::to_text(self : BatchReport) -> String {
  let out = StringBuilder()
  out.write_string(
    "MigrationLens batch: \{self.files.length()} files; exit=\{self.exit_code()}\n",
  )
  if self.initial_lock_timeout_ms is Some(value) && value < 0 {
    out.write_string("initial_lock_timeout_ms must be nonnegative\n")
  }
  for file in self.files {
    out.write_string("== \{file.migration.path} ==\n")
    out.write_string(file.report.to_text())
  }
  out.to_string()
}

///|
/// Each input is a separate SARIF run, retaining its source and completeness.
/// One invalid file report/path rejects the export; no partial log is returned.
pub fn BatchReport::to_sarif(self : BatchReport) -> Result[Json, String] {
  if self.initial_lock_timeout_ms is Some(value) && value < 0 {
    return Err("initial_lock_timeout_ms must be nonnegative")
  }
  let runs : Array[Json] = []
  for i, file in self.files {
    match file.report.to_sarif(file.migration.path) {
      Err(e) => return Err("File \{i} (\{file.migration.path}): \{e}")
      Ok(log) =>
        match log {
          { "runs": [run], .. } => {
            guard run is Object(fields) &&
              fields.get("properties") is Some(Object(properties)) else {
              return Err("Unexpected SARIF run properties")
            }
            properties["migrationLensContext"] = migration_context(
              file.migration,
              initial_lock_timeout_ms?=self.initial_lock_timeout_ms,
            )
            runs.push(run)
          }
          _ => return Err("Unexpected single-report SARIF envelope")
        }
    }
  }
  let data : Json = {
    "$schema": "https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/schemas/sarif-schema-2.1.0.json",
    "version": "2.1.0",
    "runs": Json(runs),
  }
  if self.initial_lock_timeout_ms is Some(value) && data is Object(fields) {
    fields["properties"] = { "migrationLensInitialLockTimeoutMs": value }
  }
  Ok(data)
}

///|
fn migration_context(
  input : Migration,
  initial_lock_timeout_ms? : Int32,
) -> Json {
  let context : Json = {
    "path": input.path,
    "execution": Json(input.execution),
    "initial_transaction": input.initial_transaction,
    "require_lock_timeout": input.require_lock_timeout,
    "max_lock_timeout_ms": Json(input.max_lock_timeout_ms),
  }
  if initial_lock_timeout_ms is Some(value) && context is Object(fields) {
    fields["initial_lock_timeout_ms"] = Json(value)
  }
  context
}
