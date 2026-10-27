///|
/// Checked baseline comparison retaining origin and complete source snapshots.
pub struct ArchiveDelta {
  baseline : ReviewArchive
  current : ReviewArchive
  files : Array[FileDelta]
}

///|
/// Reject project/tool/rule/database differences and changed context on every
/// common path occurrence before applying the legacy exact multiset algorithm.
/// File additions/removals/reordering remain supported. Duplicate paths pair by
/// occurrence; no rename or semantic-equivalence inference is performed.
pub fn compare_archives(
  baseline : ReviewArchive,
  current : ReviewArchive,
) -> Result[ArchiveDelta, String] {
  if baseline.origin.to_json() != current.origin.to_json() {
    return Err(
      "Incompatible archive origin: project, tool version, rule version and database must all match; regenerate both reviews with matching settings",
    )
  }
  if current.origin.database != "postgresql-18" {
    return Err("Archive comparison supports only postgresql-18")
  }
  if baseline.batch.initial_lock_timeout_ms !=
    current.batch.initial_lock_timeout_ms {
    return Err(
      "Incompatible initial session timeout; regenerate both reviews with matching settings",
    )
  }
  let paths : Map[String, Array[Migration]] = Map([])
  for file in baseline.batch.files {
    let input = file.migration
    match paths.get(input.path) {
      Some(queue) => queue.push(input)
      None => paths[input.path] = [input]
    }
  }
  let cursors : Map[String, Int32] = Map([])
  for file in current.batch.files {
    let input = file.migration
    let cursor = cursors.get(input.path).unwrap_or(0)
    if paths.get(input.path) is Some(queue) &&
      queue.get(cursor) is Some(previous) {
      if migration_context(previous) != migration_context(input) {
        return Err(
          "Incompatible execution/timeout context at \{input.path} occurrence \{cursor}; regenerate both reviews with matching settings",
        )
      }
    }
    cursors[input.path] = cursor + 1
  }
  let delta = match compare_batches(baseline.batch, current.batch) {
    Ok(delta) => delta
    Err(e) => return Err(e)
  }
  Ok({
    baseline: { origin: baseline.origin, batch: delta.baseline, },
    current: { origin: current.origin, batch: delta.current, },
    files: delta.files,
  })
}

///|
fn ArchiveDelta::legacy_delta(self : ArchiveDelta) -> BatchDelta {
  {
    baseline: self.baseline.batch,
    current: self.current.batch,
    files: self.files,
  }
}

///|
pub fn ArchiveDelta::exit_code(self : ArchiveDelta) -> Int32 {
  self.legacy_delta().exit_code()
}

///|
pub fn ArchiveDelta::to_text(self : ArchiveDelta) -> String {
  "Checked archive origin: " +
  self.current.origin.to_json().stringify() +
  "\n" +
  self.legacy_delta().to_text()
}

///|
pub fn ArchiveDelta::to_json(self : ArchiveDelta) -> Json {
  let data = self.legacy_delta().to_json()
  if data is Object(root) {
    root["format_version"] = Json(2)
    root["baseline"] = self.baseline.to_json()
    root["current"] = self.current.to_json()
  }
  data
}
