# MigrationLens

Offline PostgreSQL 18 index migration review for MoonBit tool authors.
Reports potentially blocking ordinary index operations and concurrent index
operations conflicting with a declared existing transaction. Source is retained
verbatim. Unsupported SQL is explicitly incomplete, never silently discarded.

Currently covers CREATE INDEX, DROP INDEX, BEGIN/START TRANSACTION and
COMMIT/ROLLBACK, including WORK/TRANSACTION suffixes.
BEGIN/START TRANSACTION also accept ISOLATION LEVEL (SERIALIZABLE, REPEATABLE
READ, READ COMMITTED or READ UNCOMMITTED), READ ONLY/WRITE and [NOT] DEFERRABLE.
Mode order may vary and commas between modes are optional. Repeated categories,
malformed modes and unrecognized suffixes remain incomplete; precedence is not
guessed. These starts preserve the same transaction, savepoint, timeout and
dispatch rules as plain BEGIN. READ ONLY adds ML130 for DDL/write
restrictions; DEFERRABLE adds ML131 for potential safe-snapshot waiting outside
the lock_timeout budget. Defaults, read-only enforcement and snapshot scheduling
are not inferred. Nested BEGIN still cannot change an existing transaction.
See [PostgreSQL 18 BEGIN](https://www.postgresql.org/docs/18/sql-begin.html) and
[SET TRANSACTION](https://www.postgresql.org/docs/18/sql-set-transaction.html).
`moon run cmd/main -- fixtures/transaction-modes.sql separate --require-lock-timeout --json`
reviews a rename/commit/concurrent-create workflow and exits 1. Using `simple`
also reports ML101 for the later concurrent create.

END/ABORT aliases and AND [NO] CHAIN are supported. Chaining starts a new explicit
transaction, clears savepoints/local settings and uses the committed or rolled
back session settings as its new baseline. Chaining without an explicit
transaction reports ML106; later context becomes unknown. Try
`moon run cmd/main -- fixtures/chained-transaction.sql separate --require-lock-timeout`.
The transaction semantics follow [PostgreSQL 18 COMMIT](https://www.postgresql.org/docs/18/sql-commit.html)
and [ROLLBACK](https://www.postgresql.org/docs/18/sql-rollback.html).
Execution modes distinguish
separate dispatch, a single simple-query message and an existing transaction.
Unknown context and unsupported statements produce incomplete reports.
Dispatch and initial state are independent: use `initial_transaction=true`
with `execution=SimpleQuery` when a whole file is sent inside an existing
transaction. CLI equivalent: `simple --initial-transaction`. The `transaction`
mode is shorthand for separately dispatched statements in an existing
transaction. It must not describe whole-file simple-query dispatch.
Also covers SAVEPOINT, ROLLBACK TO [SAVEPOINT], RELEASE [SAVEPOINT], and
SET [SESSION|LOCAL] lock_timeout using `=` or `TO`, RESET lock_timeout/ALL.
Timeout policy is opt-in and preserves existing callers' default behavior.
This is not a catalog validator or deployment safety certificate. Relation
kind and workload require manual review; no automatic SQL rewriting occurs.

DROP INDEX supports optional IF EXISTS, schema-qualified/quoted names,
name lists and CASCADE/RESTRICT. Concurrent drops with multiple names or
CASCADE report ML107, following [PostgreSQL 18 DROP INDEX](https://www.postgresql.org/docs/18/sql-dropindex.html).
Ordinary multi-name drops still warn about blocking access. Unsupported trailing
clauses remain incomplete. Partitioned indexes, constraint dependencies and
temporary relations require catalog knowledge and remain outside scope.
Example: `moon run cmd/main -- fixtures/drop-indexes.sql separate --json`
reports ML107 and exits 1 without needing a database.

Index maintenance also supports `REINDEX INDEX [CONCURRENTLY] name` with one
optionally schema-qualified/quoted name. It uses the same dispatch and timeout
checks as CREATE/DROP INDEX. Ordinary rebuilds report ML100; within transactions
they also report ML108 because partitioned indexes require separate handling.
Relation kind is unknown: this warning requests catalog review, not proof of
server acceptance. REINDEX TABLE/SCHEMA/DATABASE/SYSTEM remain incomplete.
Parenthesized options support CONCURRENTLY and VERBOSE (implicit true, or
TRUE/ON/1/FALSE/OFF/0), plus one TABLESPACE identifier. A named tablespace adds
ML111 because storage placement, free space and privileges need manual review.
Duplicate options, quoted booleans, unknown clauses and a CONCURRENTLY option
combined with the trailing CONCURRENTLY keyword are incomplete; precedence is
not guessed. See [PostgreSQL 18 REINDEX](https://www.postgresql.org/docs/18/sql-reindex.html).

`moon run cmd/main -- fixtures/reindex.sql separate --require-lock-timeout`
exits 0; sending that same file with `simple` reports ML101 and exits 1.
`moon run cmd/main -- fixtures/reindex-options.sql separate --require-lock-timeout`
reviews the option-bearing rebuild and exits 1 for ML111. Its tablespace is an
authored example name; the command only reviews SQL, not server existence.

Index replacement workflows support `ALTER INDEX [IF EXISTS] name RENAME TO new_name`.
The old name may be schema-qualified; the new name must be one identifier.
Renaming reports ML110 for its SHARE UPDATE EXCLUSIVE lock and possible linked
constraint rename. It participates in effective timeout policy, including
SET LOCAL in an explicit transaction. No catalog existence, name collision,
definition equivalence or atomic replacement guarantee is inferred. Other ALTER
INDEX forms are incomplete. This follows [PostgreSQL 18 ALTER INDEX](https://www.postgresql.org/docs/18/sql-alterindex.html).

`moon run cmd/main -- fixtures/replace-index.sql separate --require-lock-timeout`
reviews a complete concurrent create/drop/rename workflow and exits 1 for ML110.
Sending the whole file with `simple` additionally reports concurrent transaction
conflicts. This is an authored review example; it does not execute SQL.

Single-index storage placement supports
`ALTER INDEX [IF EXISTS] name SET TABLESPACE tablespace_name` with a quoted or
optionally schema-qualified index name and a single tablespace identifier.
ML112 warns about ACCESS EXCLUSIVE on the index. A change of tablespace may copy
its storage files; current placement, free space, privileges, ownership and
partition/temporary-relation behavior require catalog review. The opt-in timeout
policy uses the same session/local/savepoint state as other index operations.
This statement is allowed in transactions; subsequent concurrent operations are
still checked against the actual declared dispatch. IF EXISTS never establishes
that the relation exists or that a move will occur.

```mbt check
///|
test "review an index storage-placement change with bounded waiting" {
  let report = @migration_lens.review_sql(
    "SET lock_timeout=100; ALTER INDEX public.events_id_idx SET TABLESPACE pg_default;",
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
  )
  assert_true(report.complete)
  assert_eq(report.diagnostics.length(), 1)
  assert_eq(report.diagnostics[0].code, "ML112")
}
```

`moon run cmd/main -- fixtures/move-index.sql separate --require-lock-timeout --json`
reviews a storage-placement/rebuild workflow and exits 1 for ML112. Using
`simple` also reports ML101 on its concurrent rebuild. This authored fixture
names the built-in pg_default destination but only reviews SQL; it does not
execute a move or require an events table. Bulk `ALL IN TABLESPACE`, `OWNED BY`,
`NOWAIT`, schema-qualified destinations, combined actions and unknown clauses
remain incomplete. NOWAIT is supported by PostgreSQL's different bulk-move
syntax, not this single-index form. The rules follow
[PostgreSQL 18 ALTER INDEX](https://www.postgresql.org/docs/18/sql-alterindex.html).

Explicit table-lock statements support `LOCK [TABLE] [ONLY] name [*] [, ...]`
with an optional `IN mode MODE` and `NOWAIT`. Names may be quoted or schema
qualified. All eight PostgreSQL table-lock modes are recognized; omitted mode
means ACCESS EXCLUSIVE. ML120 reports the requested mode's impact: ACCESS
EXCLUSIVE can block ordinary reads and writes; SHARE, SHARE ROW EXCLUSIVE and
EXCLUSIVE can block ordinary writes; weaker modes still conflict with some
maintenance/schema operations. These are table-level locks even when named ROW.

ML121 is an error outside an active transaction block, or incomplete when that
context is unknown. A multi-statement simple-query message supplies an implicit
block, including its segment after COMMIT; a single idle LOCK does not. A known
invalid idle LOCK taints subsequent context rather than predicting execution
after an error. The timeout policy applies to waiting LOCK statements. NOWAIT
skips that statement's acquisition-timeout check, retains ML120, and does not
affect timeout checks on later statements. It rejects conflicting acquisition
immediately; it does not shorten how long acquired locks are held.

```mbt check
///|
test "review an explicit lock before an ordinary index" {
  let report = @migration_lens.review_sql(
    "BEGIN; SET LOCAL lock_timeout=100; LOCK TABLE events IN SHARE MODE NOWAIT; CREATE INDEX a ON events(id); COMMIT;",
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
  )
  assert_true(report.complete)
  assert_eq(report.diagnostics[0].code, "ML120")
  assert_eq(report.diagnostics[1].code, "ML100")
}
```

`moon run cmd/main -- fixtures/table-locks.sql separate --json` reviews an authored
index-maintenance workflow and exits 1 for ML120/ML100. Use
`--require-lock-timeout` to also report ML202 on its final concurrent index:
the transaction-local timeout has expired at COMMIT. Lock acquisition order,
descendants, view expansion, relation kind, privileges and workload still need
manual review. Acquired locks normally last until transaction end; rollback to
an earlier savepoint can release them. No lock inventory or deadlock simulation
is performed. Catalog-qualified names and `ONLY (name)` remain incomplete,
along with unsupported trailing clauses. Semantics follow [PostgreSQL 18 LOCK](https://www.postgresql.org/docs/18/sql-lock.html)
and [table-level locking](https://www.postgresql.org/docs/18/explicit-locking.html#LOCKING-TABLES).

## Standalone vacuum maintenance

VACUUM covers the documented legacy keyword order FULL, FREEZE, VERBOSE, ANALYZE,
and parenthesized FULL/FREEZE/VERBOSE/ANALYZE/SKIP_LOCKED/TRUNCATE booleans plus
INDEX_CLEANUP AUTO/ON/OFF. Explicit false is honored; duplicate options and mixed
legacy/parenthesized syntax remain incomplete. Relation lists support the same
quoted/schema-qualified names and ONLY/inheritance markers as ANALYZE. Column
lists require explicitly enabled ANALYZE: otherwise they are rejected rather
than discarded. PARALLEL, BUFFER_USAGE_LIMIT, PROCESS_MAIN/TOAST, database-stats
and other unlisted options are outside this subset.

ML150 distinguishes ordinary SHARE UPDATE EXCLUSIVE maintenance from FULL's
ACCESS EXCLUSIVE table rewrite and disk-space demand. ML152 warns that ordinary
vacuum may also request ACCESS EXCLUSIVE for tail-page truncation unless
TRUNCATE FALSE is explicit. ML153 flags INDEX_CLEANUP OFF for follow-up cleanup;
FULL ignores both of those options. ML154 flags an omitted relation list's
database-wide scope. AUTO/ON do not guarantee cleanup or reclaimed disk space.

ML151 rejects explicit/caller/implicit transaction blocks, including a segment
after COMMIT in a multi-statement simple-query message. Unknown context yields
incomplete coverage. An invalid VACUUM taints later context rather than assuming
SQL runs past a server error. A single idle simple-query VACUUM is allowed by
this rule set. SKIP_LOCKED retains timeout checks because other waits remain;
lock_timeout does not bound total maintenance duration.

```mbt check
///|
test "review a standalone bounded-wait maintenance operation" {
  let report = @migration_lens.review_sql(
    "VACUUM (ANALYZE, TRUNCATE FALSE, INDEX_CLEANUP ON) events(id);",
    execution=SeparateStatements,
    initial_lock_timeout_ms=100,
    max_lock_timeout_ms=100,
  )
  assert_true(report.complete)
  assert_eq(report.diagnostics.map(d => d.code), ["ML150"])
}
```

`moon run cmd/main -- fixtures/vacuum.sql separate --require-lock-timeout --json`
reviews a concurrent-rebuild/vacuum workflow and exits 1 for ML150. Using
`simple` also reports ML101 and ML151 for transaction conflicts. The example
does not execute SQL. Catalog state, table kind, privileges, descendant expansion,
bloat, wraparound failsafe and runtime lock contention require database checks.
The rules follow [PostgreSQL 18 VACUUM](https://www.postgresql.org/docs/18/sql-vacuum.html).

## Statistics refresh after index maintenance

`ANALYZE [VERBOSE] [table_and_columns, ...]` and parenthesized boolean options
VERBOSE/SKIP_LOCKED are covered. Booleans accept omitted true, TRUE/ON/1 and
FALSE/OFF/0. Targets allow quoted or schema-qualified names, ONLY, an optional
inheritance `*`, and nonempty simple column lists. ONLY combined with `*`,
catalog qualification, expressions, duplicate/unknown options, BUFFER_USAGE_LIMIT
and extra clauses remain incomplete. No source data is discarded or rewritten.

ML140 identifies SHARE UPDATE EXCLUSIVE lock contention and sampling/plan-change
work. An omitted relation list additionally produces ML141 for database-wide
scope. SKIP_LOCKED can skip busy relations and still wait on indexes or sample
rows, so it retains the effective lock_timeout check. ANALYZE does not change
modeled transaction/timeout state. Privileges, relation kinds, descendant
expansion, sampled rows and the resulting statistics require database knowledge.

```mbt check
///|
test "review statistics collection after a concurrent index" {
  let report = @migration_lens.review_sql(
    "SET lock_timeout=100; CREATE INDEX CONCURRENTLY a ON events(id); ANALYZE (SKIP_LOCKED) events(id);",
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
  )
  assert_true(report.complete)
  assert_eq(report.diagnostics.map(d => d.code), ["ML140"])
}
```

`moon run cmd/main -- fixtures/analyze.sql separate --require-lock-timeout --json`
reviews the complete index/statistics workflow and exits 1 for ML140. Sending
it with `simple` additionally reports ML101 for the concurrent index. The CLI
uses no database. Semantics follow [PostgreSQL 18 ANALYZE](https://www.postgresql.org/docs/18/sql-analyze.html)
and [table locks](https://www.postgresql.org/docs/18/explicit-locking.html#LOCKING-TABLES).

```mbt check
///|
test "review an index migration" {
  let report = @migration_lens.review_sql(
    "CREATE INDEX CONCURRENTLY events_id_idx ON events (id);",
    execution=ExistingTransaction,
  )
  assert_eq(report.exit_code(), 1)
  assert_eq(report.diagnostics[0].code, "ML101")
}
```

## End-to-end example

From the repository root with MoonBit stable installed:

```text
moon update
moon run cmd/main -- fixtures/postgres-migrations-concurrent.sql separate
moon run cmd/main -- fixtures/postgres-migrations-concurrent.sql transaction --json
```

The first review exits 0; the second reports ML101 and exits 1. The input is
copied from a migration runner's integration test, not production data. Its
fixed revision and MIT notice are in [THIRD_PARTY.md](THIRD_PARTY.md).
No database or private infrastructure is required.

Compare the same multi-statement migration under two runner configurations:

```text
moon run cmd/main -- fixtures/batch-indexes.sql separate
moon run cmd/main -- fixtures/batch-indexes.sql simple
```

Separate dispatch exits 0; one simple-query message reports ML101 and exits 1.
A COMMIT inside such a message does not make its following statement individually
dispatched. Runner-specific comments are ordinary comments; callers must supply
the mode after inspecting the runner. Unknown earlier statements taint later
context. Diagnostics describe static constraints assuming preceding supported
statements succeed; this is not an execution trace after a runtime failure.

## Check an effective lock timeout

```text
moon run cmd/main -- fixtures/session-timeout.sql separate --require-lock-timeout --json
moon run cmd/main -- fixtures/savepoint-timeout.sql separate --require-lock-timeout
```

The first exits 0: the session setting applies to the separately dispatched
concurrent index. The second exits 1: rollback to the savepoint cancels the
finite local timeout (ML201), and an ordinary index also produces ML100.
Library callers opt in with `require_lock_timeout=true` on `review_sql`.

Set `max_lock_timeout_ms=2000` to also require that the effective timeout is
at most 2,000 milliseconds. The maximum implies the finite-timeout check;
it need not be combined with `require_lock_timeout`. Equality passes, larger
values report ML205 with the effective milliseconds, disabled/unknown values
still report ML201/ML202. Omitted limits preserve previous behavior. Limits
outside 1..2147483647 report ML011 and incomplete analysis (no SQL statements
are analyzed). This is a caller policy, not a PostgreSQL server restriction.

```mbt check
///|
test "bound lock waiting in a migration policy" {
  let report = @migration_lens.review_sql(
    "SET lock_timeout='10s'; CREATE INDEX CONCURRENTLY a ON t (id);",
    execution=SeparateStatements,
    max_lock_timeout_ms=2000,
  )
  assert_eq(report.diagnostics[0].code, "ML205")
}
```

CLI: `moon run cmd/main -- fixtures/timeout-limit.sql separate --max-lock-timeout-ms=2000 --json`
exits 1; use 10000 for an exit-0 comparison. Invalid or repeated maximum
options exit 2. Numeric values are tracked through the same savepoint,
commit/rollback and chain rules as the finite-timeout policy.

Initial timeout values are unknown unless explicitly supplied, not assumed zero.
RESET/DEFAULT targets remain unknown even when an initial current value is supplied. Positive finite
timeouts established by this input satisfy the policy; zero reports ML201,
unknown reports ML202. SET LOCAL outside a transaction reports ML200 even when
the policy is off because the setting has no effect. SET and SET LOCAL are
transactional; rollback restores earlier values, commit discards local settings,
and release retains current settings while removing the savepoint and its
descendants. Duplicate savepoint names select the most recent surviving entry.
Unknown SQL taints both transaction and timeout state.

## Known session timeout at file entry

Supply `initial_lock_timeout_ms` when the caller can assure the session-level
setting at file entry and there is no unmodeled SET LOCAL override. It accepts
0 (disabled) through 2147483647 milliseconds; omission means unknown. This is a
fact about the connection, not a command that changes it or a policy switch.
Use `require_lock_timeout` or `max_lock_timeout_ms` to enable the corresponding
review policy. Negative initial values produce ML012 and incomplete analysis.

```mbt check
///|
test "review a connection configured outside the migration" {
  let report = @migration_lens.review_sql(
    "CREATE INDEX CONCURRENTLY a ON t (id);",
    execution=SeparateStatements,
    require_lock_timeout=true,
    initial_lock_timeout_ms=2000,
  )
  assert_eq(report.exit_code(), 0)
}
```

`moon run cmd/main -- fixtures/postgres-migrations-concurrent.sql separate --require-lock-timeout --initial-lock-timeout-ms=2000`
exits 0; an initial value of 0 reports ML201 and exits 1. SET, SET LOCAL,
savepoints, commit, rollback and chaining then update the supplied state using
the normal rules. RESET/DEFAULT is not inferred from this current-session fact.
When the file starts inside an existing transaction, its earlier rollback
baseline is unknown: rolling it back discards certainty about the supplied
value. Unknown SQL also discards certainty, and an initial value never fixes
unknown dispatch. Existing text/JSON behavior is preserved when the option is
omitted. Single-file version-1 JSON remains the same report model.

Timeout values: nonnegative integer milliseconds, DEFAULT, or quoted integer
durations with `ms`, `s`, `min`, `h`, `d`, at most 2,147,483,647 milliseconds.
Fractions, expressions, other units/settings and overflows report incomplete;
they are not rounded or discarded. Savepoint names support ASCII identifiers
up to 63 decoded bytes, including quoted/escaped quotes and case sensitivity.
Longer/non-ASCII names are incomplete because server truncation is byte-based.
External savepoint targets not established in this input are incomplete.

Timeout policy does not assess statement_timeout, index validity, catalog
existence, partition rules, data size or lock duration. A finite lock timeout
does not make an index operation safe. More DDL and caller-supplied relation
facts remain roadmap items.

Import `cn-xjr/migration_lens`. Public API: `review_sql`, `Execution`, `Report`,
`Diagnostic`, `Severity`, `Span`. Reports provide `exit_code`, `to_text` and
versioned deterministic `to_json`. Spans use half-open UTF-16 code-unit offsets;
text positions are one-based UTF-16 columns and lines.

## Independent multi-file review

Use `Migration::new(path, source, execution=...)` and
`review_migrations(inputs[:])` for several independent inputs. Each migration
has its own execution, initial-transaction and timeout policy. Input order,
duplicate path labels, all source and diagnostics are retained. A file with an
incomplete analysis never prevents later files from being reviewed. State does
not flow between files: this API does not model a runner sending several files
through one shared transaction/session.

```mbt check
///|
test "review a migration list without sharing transaction state" {
  let inputs = [
    @migration_lens.Migration::new(
      "001.sql",
      "BEGIN;",
      execution=SeparateStatements,
    ),
    @migration_lens.Migration::new(
      "002.sql",
      "DROP INDEX CONCURRENTLY a;",
      execution=SeparateStatements,
    ),
  ]
  let batch = @migration_lens.review_migrations(inputs[:])
  assert_eq(batch.exit_code(), 1)
  assert_eq(batch.files[1].report.exit_code(), 0)
}
```

`BatchReport` exposes `files` (`FileReport` migration/report pairs), `exit_code`,
`to_text`, version-1 `to_json` and fallible `to_sarif`. Aggregate exit codes are
the maximum file code: incomplete 2, findings 1, clean 0. SARIF emits one run
per input, including duplicate paths, preserving each run's completion status.
An invalid path/report rejects the entire SARIF export. The pure library accepts
an empty list and returns exit 0; the CLI requires an explicit nonempty list.
File reports retain their original `migration`; JSON and SARIF run properties
include its execution and timeout policy so repeated path labels remain auditable.

From the repository root:

```text
moon run cmd/batch -- fixtures/review-manifest.json --json
moon run cmd/batch -- fixtures/review-manifest.json --sarif
```

Both examples review three files and exit 2 while retaining the clean,
warning and incomplete reports. With no format flag, the CLI prints text.
The manifest contains `format_version: 1` and a `migrations` array. An optional
top-level `initial_lock_timeout_ms` supplies the same starting session fact for
each independent file; it never flows from an earlier file. `BatchReport` exposes
that fact, and JSON/SARIF records it when supplied. It is a common connection
setting, not a per-entry field. Try
`moon run cmd/batch -- fixtures/review-session-manifest.json --json` (exit 0).
Every entry
requires `path` and `execution` (`separate`, `simple`, `transaction`, `unknown`),
and optionally boolean `initial_transaction` / `require_lock_timeout` and a
positive integer `max_lock_timeout_ms` up to 2147483647. Paths are resolved from
the process working directory, not the manifest directory; they must be relative
with no empty/dot/parent components, drives, schemes or control characters.
Windows separators normalize to `/`. Duplicate file entries are permitted.

Unknown fields, duplicate decoded JSON keys, invalid Unicode/types/policies,
unsupported versions, more than 16 nesting levels, over 1,000,000 UTF-16 units,
empty lists or more than 1,000 entries are rejected. Every SQL file is strictly
decoded as UTF-8 before analysis. A missing/unreadable file or invalid manifest
returns an actionable error and exit 2, without a partial batch report. SQL
coverage failures instead remain per-file reports. This workflow does not
execute SQL, upload reports or require database infrastructure.

## Restore and render saved reports offline

`Report::parse_json(text)` returns `Result[Report, String]` for the version-1
single-report JSON contract. It preserves the SQL, statement count, completion
flag and every diagnostic in order. Unknown/missing fields, duplicate decoded
keys, unsupported versions, invalid types/Unicode, out-of-range UTF-16 spans,
surrogate-splitting offsets and contradictory completion are rejected with a
diagnostic path. Numeric fields require plain nonnegative decimal integer tokens;
fractions, exponents and negative zero are rejected before floating-point
rounding. Batch envelopes are not accepted. This validates the stored
structure; it does not rescan SQL or certify the report's original conclusions.

```mbt check
///|
test "restore a saved report without discarding findings" {
  let original = @migration_lens.review_sql(
    "DROP INDEX events_id_idx;",
    execution=SeparateStatements,
  )
  let restored = @migration_lens.Report::parse_json(
    original.to_json().stringify(),
  ).unwrap()
  assert_eq(restored, original)
  assert_eq(restored.to_text(), original.to_text())
}
```

The end-to-end script writes UTF-8 saved reports from the real migration-runner
and River fixtures. From the repository root:

```text
moon run scripts/e2e.mbtx wasm
moon run cmd/report -- _build/saved-report-2.json text
moon run cmd/report -- _build/saved-report-2.json sarif fixtures/river-006-bulk-unique.sql
moon run cmd/report -- _build/saved-report-0.json json
```

The first two render commands retain the incomplete review's exit code 2; the
last exits 0 and reproduces the canonical single-report JSON. Formats are
`text`, `json` or `sarif`; only SARIF requires a repository-relative SQL artifact
path. Read/UTF-8/validation/export failures exit 2 with an actionable message.
No database, original SQL file or new analysis is needed to render a saved
report. Source embedded in the report is retained; sharing it exposes that SQL.

## Restore a batch review archive

`BatchReport::parse_json(text)` restores the version-1 batch report, including
ordered duplicate paths, source, execution/policy snapshots, diagnostics and
the optional shared initial timeout. It validates aggregate exit codes, repeated
path/initial facts, numeric bounds, duplicate decoded keys and unknown fields.
An unrepresentable field rejects the whole input. It never reads or rescans SQL.

The saved-report contract differs from the input manifest: execution uses enum
names such as `SeparateStatements`, and the existing optional maximum is encoded
as `null` or `[integer]`. Signed 32-bit policy values and their invalid-policy
reports are preserved, including the canonical configuration-error message.
Integer tokens reject fractions/exponents/negative zero before rounding. Empty
batches are supported. Invalid file labels remain intact; SARIF export rejects
invalid paths without emitting a partial log. Restoration validates structure,
not the original report's conclusions. The single-report CLI stays unchanged.

```text
moon run scripts/e2e.mbtx wasm
moon run cmd/report_batch -- _build/saved-batch-2.json text
moon run cmd/report_batch -- _build/saved-batch-2.json sarif
moon run cmd/report_batch -- _build/saved-batch-0.json json
```

The first two render commands exit 2 while retaining every incomplete/covered
file; the last exits 0 and reproduces canonical JSON. The script archives real
upstream fixture reviews and an authored warning workflow. Formats are `text`,
`json`, `sarif`; stored path labels supply SARIF locations. Read/UTF-8/schema or
export errors produce an actionable message and exit 2. No original files,
database or private infrastructure are needed to inspect an archive.

## Compare a trusted baseline with the current report

`compare_reports(baseline, current)` returns `Result[ReportDelta, String]`.
Both reports must be complete and structurally valid, even for library callers
constructing reports directly. The caller must select the same logical artifact,
rule version and review context/policies; version-1 reports do not record enough
context to verify this automatically. A baseline is a trusted acceptance decision.

Identity is the exact rule ID, severity, message, help and SQL text selected by
the diagnostic's span. Position changes alone are ignored. No whitespace,
identifier, comment or semantic normalization occurs. Duplicate occurrences are
matched by count, in input order; an extra copy is new. Matching spans may be
relocated between revisions, so this does not establish statement identity or
preserve its surrounding context. Review source changes alongside the delta.

`ReportDelta` retains both complete original reports (with independent diagnostic
array snapshots), ordered `introduced`/`resolved` findings and a `retained` count.
Spans refer to current source for introduced findings and baseline source for
resolved findings. Version-1 `to_json` includes both full reports; `to_text`
shows the delta. No findings disappear from the retained source reports.
Its baseline gate exits 1 for any introduced finding, otherwise 0. Existing
errors can therefore remain in a delta that exits 0; use the current report's
own `exit_code` for an absolute gate. Incomplete/invalid inputs fail comparison
and the CLI exits 2, never a passing partial result. Delta JSON is its own
output contract, not a single report accepted by `Report::parse_json`.

```text
moon run scripts/e2e.mbtx wasm
moon run cmd/compare -- _build/comparison-0.json _build/comparison-1.json --json
moon run cmd/compare -- _build/comparison-1.json _build/comparison-1.json
moon run cmd/compare -- _build/comparison-1.json _build/comparison-0.json --json
```

These render an added ordinary DROP INDEX (exit 1), the accepted same findings
(exit 0), and resolved findings (exit 0). The script creates both reports from
the same real migration-runner fixture under separate dispatch; its current
revision appends an authored `DROP INDEX obsolete_index;` review example.
Neither SQL nor reports require a database or a hosted CI account. This workflow
does not automatically create/update a baseline, suppress the current report,
compare batch manifests or perform SQL rewriting.

## Compare complete batch archives

`compare_batches(baseline, current)` returns `Result[BatchDelta, String]` for
trusted reports from the same project/rule version. Both batches must have
complete, valid reports and valid execution/policy contexts. Any invalid or
incomplete file rejects the whole comparison, including incomplete files that
would otherwise be removed. Invalid empty-batch configuration is also rejected.

Files match by exact path label, execution, initial transaction, timeout policy
and shared initial-timeout fact. File reordering is supported; duplicate keys
pair by occurrence in each input. Reordering different SQL under an identical
duplicate key can produce new findings. Path spelling and context changes are
removals/additions; no path normalization, rename detection or fuzzy matching
occurs. Within matched files, the single-report exact diagnostic multiset rules
apply. Use stable distinct labels when migrations need independent identities.

`BatchDelta` retains independent `baseline` and `current` snapshots. Its `files`
contains `FileDelta` records: optional zero-based `baseline_index`/`current_index`,
ordered `introduced`/`resolved` diagnostics and a `retained` count. Current entries
appear first in current order, followed by unmatched baseline entries in baseline
order. Every input file appears exactly once per side, including clean files.
Spans refer to the corresponding input snapshot. Delta JSON version 1 encodes
indices as integers or null and includes both full batch reports. It is distinct
from the saved-batch input contract. Text output labels both source sides.

```text
moon run scripts/e2e.mbtx wasm
moon run cmd/compare_batch -- _build/saved-batch-0.json _build/saved-batch-1.json --json
moon run cmd/compare_batch -- _build/saved-batch-1.json _build/saved-batch-1.json
moon run cmd/compare_batch -- _build/saved-batch-1.json _build/saved-batch-0.json --json
```

These show added findings (exit 1), accepted existing findings (exit 0), and
resolved findings (exit 0). Read/UTF-8/validation/coverage failures exit 2. A
baseline gate checks only new findings; the full current snapshot retains its
own absolute exit code and all existing diagnostics. It does not update the
trusted baseline automatically. No original SQL files or database are required.

## SARIF reports for code scanning

`Report::to_sarif(artifact_path)` returns `Result[Json, String]` containing
SARIF 2.1.0. Every diagnostic remains a result; repeated rule IDs share a rule
descriptor without merging findings. Error and incomplete diagnostics have
SARIF level `error`, warnings have `warning`; the original severity, message,
help and UTF-16 span are retained in result properties. The original SQL is
embedded in the artifact. Reports can contain sensitive SQL, so review them
before sharing. Incomplete analysis sets `executionSuccessful=false`; covered
findings still count as a successful scan with exit code 1.

```mbt check
///|
test "export an incomplete review without hiding findings" {
  let report = @migration_lens.review_sql(
    "SELECT 1;",
    execution=SeparateStatements,
  )
  assert_eq(report.exit_code(), 2)
  assert_true(report.to_sarif("migrations/001.sql") is Ok(_))
}
```

Run from the repository root:

```text
moon run cmd/main -- fixtures/batch-indexes.sql simple --sarif
moon run cmd/main -- fixtures/river-006-bulk-unique.sql separate --sarif
```

The first exits 1, the second 2; stdout contains SARIF in both cases. Capture
stdout with a UTF-8-aware process runner and retain the exit code as your CI
gate. `--sarif` and `--json` are mutually exclusive. SARIF paths must be relative
to the repository, with no absolute/drive/scheme paths or empty/dot/parent
components. Backslashes normalize to slashes; Unicode and reserved URI bytes
are percent-encoded. For this output use `fixtures/file.sql`, not `./fixtures/file.sql`.
Invalid paths or externally constructed reports with invalid spans, metadata
or Unicode return `Err`; the CLI exits 2. No findings are silently removed.
Coordinates use UTF-16 columns and CRLF/CR/LF line breaks; zero-width EOF spans
are retained. Existing text and version-1 JSON output are unchanged.

The format follows the [OASIS SARIF 2.1.0 specification](https://docs.oasis-open.org/sarif/sarif/v2.1.0/os/sarif-v2.1.0-os.html).
Local schema validation does not establish acceptance by a particular hosted
code scanning service; no upload, hosting account or private infrastructure is
needed to generate and inspect these reports.

This is an unpublished source checkout, not a Mooncakes release. Run the examples
from this repository; no `moon add` installation is claimed yet. The JS CLI uses
Node.js. Browser execution and macOS execution have not been tested locally.

Exit codes: 0 = no findings within the documented rule set; 1 = findings on
covered input; 2 = incomplete analysis or CLI input failure. CI should reject
both 1 and 2. Unknown execution is never assumed to be autocommit.

Lexical input supports standard strings without backslashes, quoted identifiers,
line/nested block comments and dollar-quoted bodies (which remain opaque).
psql commands, COPY data streams, templates and dynamic SQL are unsupported.
Valid PostgreSQL outside the pinned parser subset also returns incomplete.
Input limit: 1,000,000 UTF-16 units; NUL is rejected. Index syntax nesting is
limited to 128 levels. The file adapter strictly decodes UTF-8 and rejects
malformed bytes. The library itself accepts MoonBit strings, not byte streams.

## Table reordering after index changes

CLUSTER accepts a single optional-schema table with optional `USING index`,
or no target, with legacy VERBOSE or a parenthesized VERBOSE boolean. ML160
warns about ACCESS EXCLUSIVE locks, rewrite space and follow-up ANALYZE.
ML161 identifies database-wide scope; ML162 rejects that form in known
transaction blocks and reports incomplete when context is uncertain. Named
ordinary tables are allowed in blocks. ML163 requires catalog checks: a
partitioned table needs USING and cannot run in a block; an omitted index needs
a remembered clustering index. No partition kind or index suitability is inferred.
Old `index ON table` syntax, multiple targets and unconsumed clauses yield ML003.

```mbt check
///|
test "review a targeted table reorder" {
  let report = @migration_lens.review_sql(
    "SET lock_timeout=100; CLUSTER public.events USING events_id; ANALYZE events;",
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
  )
  assert_true(report.complete)
  assert_eq(report.diagnostics.map(d => d.code), ["ML160", "ML163", "ML140"])
}
```

`moon run cmd/main -- fixtures/cluster.sql separate --require-lock-timeout --json`
reviews the full workflow without a database and exits 1 for those three warnings.
Changing dispatch to `simple` still permits a named ordinary-table CLUSTER;
this does not prove a catalog-dependent target is valid. Semantics follow
[PostgreSQL 18 CLUSTER](https://www.postgresql.org/docs/18/sql-cluster.html).

## Development

```text
moon fmt
moon info
moon check --target all --deny-warn
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon test --target native --deny-warn
moon run scripts/e2e.mbtx wasm
moon run scripts/e2e.mbtx js
moon run scripts/e2e.mbtx native
```

CI covers Linux, macOS and Windows; native runtime tests run on Linux/macOS.
A workflow definition does not establish a passed remote run. See
[design](docs/design.md) for scenarios, evidence and capability roadmap.
The e2e script always runs as a Wasm-hosted script and selects the CLI target
with its argument. Set `MIGRATIONLENS_MOON` if the executable is not named moon.
See [validation](docs/validation.md) for reproducible PostgreSQL probes and
local execution evidence, including environment limitations.

Apache-2.0; third-party fixtures and dependencies retain their own licenses.
