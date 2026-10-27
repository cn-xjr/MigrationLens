# Provenance-checked review archives

Use `ReviewArchive::review` for persisted CI reviews. Version 2 adds project,
tool version, rule version and database identity to the existing batch format.
One SQL file is a one-entry batch, retaining every execution and timeout fact.

```mbt check
///|
test "a one-file archive retains execution facts across restoration" {
  let archive = @migration_lens.ReviewArchive::review(
    "orders-service",
    [
      @migration_lens.Migration::new(
        "migrations/001.sql",
        "DROP INDEX old_idx;",
        execution=SeparateStatements,
        max_lock_timeout_ms=100,
      ),
    ][:],
    initial_lock_timeout_ms=50,
  ).unwrap()
  let saved = @migration_lens.ReviewArchive::parse_json(
    archive.to_json().stringify(),
  ).unwrap()
  assert_eq(saved.origin.project, "orders-service")
  assert_eq(saved.batch.initial_lock_timeout_ms, Some(50))
  assert_eq(
    @migration_lens.compare_archives(archive, saved).unwrap().exit_code(),
    0,
  )
  assert_eq(saved.exit_code(), 1)
}
```

`compare_archives` rejects a difference in project, tool version, rule version,
database or shared initial timeout. For each common path, paired by occurrence,
it also rejects changed execution, initial transaction, finite-timeout requirement
or maximum timeout. File order may change; additions and removals are represented
in the delta. Duplicate paths pair in occurrence order. A renamed path is treated
as a removal and addition; keep distinct stable path labels.

```mbt check
///|
test "archive comparison refuses incompatible contexts with identical SQL" {
  let make = mode => {
    @migration_lens.ReviewArchive::review(
      "orders-service",
      [
        @migration_lens.Migration::new(
          "001.sql",
          "DROP INDEX a;",
          execution=mode,
        ),
      ][:],
    ).unwrap()
  }
  assert_true(
    @migration_lens.compare_archives(
      make(SeparateStatements),
      make(SimpleQuery),
    )
    is Err(_),
  )
}
```

The gate returns 1 for introduced findings, otherwise 0. Incomplete/invalid
inputs return Err and must yield a failing integration status, never a pass.
The current archive's own exit code still describes absolute findings (0/1/2).
Retained findings, every source and provenance remain in ArchiveDelta and its
version-2 JSON. Comparison snapshots diagnostic arrays independently.

## Format and compatibility

The outer object contains exactly `format_version: 2`, `origin` and `batch`.
Origin contains exactly `project`, `tool_version`, `rules_version`, `database`;
the nested batch uses the existing version-1 contract. Decoding rejects duplicate
keys, unsupported envelopes, unrepresented fields, invalid Unicode/ranges and
inconsistent batch metadata. It does not rerun SQL analysis. Source is retained
verbatim, including incomplete SQL. Origin strings require 1..256 UTF-16 units,
without surrounding whitespace or control characters.

New reviews record tool `0.1.0`, rules `pg18-review-1` and database `postgresql-18`.
Unknown nonempty version strings can be restored for inspection; comparison
requires identical origins and the supported database. Regenerate baseline and
current reviews together when tool/rules change. Maintainers must bump the rule
identity when analysis semantics change; format version is independent.

Existing Report/BatchReport v1 encoders, decoders and comparisons are unchanged.
Old artifacts can still be viewed through those decoders or `cmd/report` and
`cmd/report_batch`. V1 single reports lack execution provenance; v1 batches lack
tool/rule/project identity. They are not automatically promoted into v2:
regenerate from SQL with explicit project and runner facts. Legacy comparison
retains its caller-assurance contract; new archive comparison checks compatibility.

`ReviewArchive::to_text`, `to_json` and fallible `to_sarif` provide delivery formats.
SARIF retains origin and context in run properties and driver tool version.
Export rejects invalid paths instead of dropping files. Empty batches retain
origin in JSON but produce no SARIF runs.

Provenance is declared metadata, not a signature. Select a trusted accepted
baseline and review SQL changes alongside the delta. No baseline acceptance,
SQL rewriting or database I/O occurs automatically.
