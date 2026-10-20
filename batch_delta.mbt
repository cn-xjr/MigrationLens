///|
/// Indices are zero-based into BatchDelta.baseline/current; None marks absence.
/// Findings use current spans for introduced items and baseline spans for resolved.
pub struct FileDelta {
  baseline_index : Int32?
  current_index : Int32?
  introduced : Array[Diagnostic]
  resolved : Array[Diagnostic]
  retained : Int32
}

///|
/// Current-file order followed by unmatched baseline files in baseline order.
pub struct BatchDelta {
  baseline : BatchReport
  current : BatchReport
  files : Array[FileDelta]
}

///|
fn checked_batch_snapshot(
  batch : BatchReport,
  label : String,
) -> Result[BatchReport, String] {
  if batch.initial_lock_timeout_ms is Some(n) && n < 0 {
    return Err("\{label}: invalid initial timeout")
  }
  let files = []
  for i, file in batch.files {
    let input = file.migration
    if !valid_unicode(input.path) || input.source != file.report.source {
      return Err(
        "\{label} file \{i}: invalid Unicode path or mismatched source",
      )
    }
    if input.execution == Unknown ||
      (input.max_lock_timeout_ms is Some(n) && n <= 0) {
      return Err(
        "\{label} file \{i}: unknown execution or invalid timeout policy",
      )
    }
    match validate_report(file.report, "\{label} file \{i}") {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    if !file.report.complete {
      return Err(
        "\{label} file \{i}: analysis is incomplete; a batch baseline requires complete coverage",
      )
    }
    files.push({ migration: input, report: report_snapshot(file.report), })
  }
  Ok({ files, initial_lock_timeout_ms: batch.initial_lock_timeout_ms, })
}

///|
fn file_delta(
  before : Int32?,
  after : Int32?,
  delta : ReportDelta,
) -> FileDelta {
  {
    baseline_index: before,
    current_index: after,
    introduced: delta.introduced,
    resolved: delta.resolved,
    retained: delta.retained,
  }
}

///|
/// Match exact path/context keys, then duplicate occurrences in source order.
/// Context includes shared initial timeout. Changed paths/policies are removals
/// and additions; SQL source itself is compared using compare_reports. The caller
/// must select trusted reports from the same project and rule version.
///
/// ```mbt check
/// test {
///   let inputs = [
///     @migration_lens.Migration::new(
///       "a.sql",
///       "DROP INDEX a;",
///       execution=SeparateStatements,
///     ),
///   ]
///   let batch = @migration_lens.review_migrations(inputs[:])
///   let delta = @migration_lens.compare_batches(batch, batch).unwrap()
///   assert_eq(delta.files[0].retained, 1)
///   assert_eq(delta.exit_code(), 0)
/// }
/// ```
pub fn compare_batches(
  baseline : BatchReport,
  current : BatchReport,
) -> Result[BatchDelta, String] {
  let baseline = match checked_batch_snapshot(baseline, "Baseline") {
    Ok(b) => b
    Err(e) => return Err(e)
  }
  let current = match checked_batch_snapshot(current, "Current") {
    Ok(b) => b
    Err(e) => return Err(e)
  }
  let queues : Map[String, Array[Int32]] = Map([])
  for i, file in baseline.files {
    let key = migration_context(
      file.migration,
      initial_lock_timeout_ms?=baseline.initial_lock_timeout_ms,
    ).stringify()
    match queues.get(key) {
      Some(indices) => indices.push(i)
      None => queues[key] = [i]
    }
  }
  let cursors : Map[String, Int32] = Map([])
  let used : Map[Int32, Unit] = Map([])
  let files = []
  let empty : Report = {
    source: "",
    statements: 0,
    complete: true,
    diagnostics: [],
  }
  for i, file in current.files {
    let key = migration_context(
      file.migration,
      initial_lock_timeout_ms?=current.initial_lock_timeout_ms,
    ).stringify()
    let cursor = cursors.get(key).unwrap_or(0)
    let before = match queues.get(key) {
      Some(indices) => indices.get(cursor)
      None => None
    }
    let previous = match before {
      Some(index) => {
        cursors[key] = cursor + 1
        used[index] = ()
        baseline.files[index].report
      }
      None => empty
    }
    let delta = match compare_reports(previous, file.report) {
      Ok(d) => d
      Err(e) => return Err(e)
    }
    files.push(file_delta(before, Some(i), delta))
  }
  for i, file in baseline.files {
    if !used.contains(i) {
      let delta = match compare_reports(file.report, empty) {
        Ok(d) => d
        Err(e) => return Err(e)
      }
      files.push(file_delta(Some(i), None, delta))
    }
  }
  Ok({ baseline, current, files, })
}

///|
/// Baseline gate only: retained findings remain in the full current snapshot.
pub fn BatchDelta::exit_code(self : BatchDelta) -> Int32 {
  if self.files.any(file => !file.introduced.is_empty()) {
    1
  } else {
    0
  }
}

///|
fn delta_index_json(index : Int32?) -> Json {
  match index {
    Some(i) => Json(i)
    None => Json::null()
  }
}

///|
pub fn BatchDelta::to_json(self : BatchDelta) -> Json {
  let files : Array[Json] = self.files.map(file => {
    "baseline_index": delta_index_json(file.baseline_index),
    "current_index": delta_index_json(file.current_index),
    "introduced": Json(file.introduced),
    "resolved": Json(file.resolved),
    "retained": file.retained,
  })
  {
    "format_version": 1,
    "baseline": self.baseline.to_json(),
    "current": self.current.to_json(),
    "files": Json(files),
    "exit_code": self.exit_code(),
  }
}

///|
pub fn BatchDelta::to_text(self : BatchDelta) -> String {
  let out = StringBuilder()
  out.write_string(
    "MigrationLens batch delta: \{self.files.length()} entries; exit=\{self.exit_code()}\n",
  )
  for file in self.files {
    let before = match file.baseline_index {
      Some(i) => Some(self.baseline.files[i])
      None => None
    }
    let after = match file.current_index {
      Some(i) => Some(self.current.files[i])
      None => None
    }
    let path = match after {
      Some(f) => f.migration.path
      None => before.unwrap().migration.path
    }
    out.write_string(
      "== \{path} baseline=\{Repr(file.baseline_index)} current=\{Repr(file.current_index)}; \{file.retained} retained ==\n",
    )
    if after is Some(f) {
      let report : Report = {
        source: f.report.source,
        statements: f.report.statements,
        complete: true,
        diagnostics: file.introduced,
      }
      out.write_string("Introduced (current source):\n" + report.to_text())
    }
    if before is Some(f) {
      let report : Report = {
        source: f.report.source,
        statements: f.report.statements,
        complete: true,
        diagnostics: file.resolved,
      }
      out.write_string("Resolved (baseline source):\n" + report.to_text())
    }
  }
  out.to_string()
}
