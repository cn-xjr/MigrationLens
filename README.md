# MigrationLens

Offline PostgreSQL 18 index migration review for MoonBit tool authors.
Reports potentially blocking ordinary index operations and concurrent index
operations conflicting with a declared existing transaction. Source is retained
verbatim. Unsupported SQL is explicitly incomplete, never silently discarded.

Currently covers CREATE INDEX, DROP INDEX, BEGIN/START TRANSACTION and
COMMIT/ROLLBACK, including WORK/TRANSACTION suffixes.
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
server acceptance. REINDEX TABLE/SCHEMA/DATABASE/SYSTEM and parenthesized options
are explicitly incomplete. See [PostgreSQL 18 REINDEX](https://www.postgresql.org/docs/18/sql-reindex.html).

`moon run cmd/main -- fixtures/reindex.sql separate --require-lock-timeout`
exits 0; sending that same file with `simple` reports ML101 and exits 1.

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

Initial/default timeout values are unknown, not assumed zero. Positive finite
timeouts established by this input satisfy the policy; zero reports ML201,
unknown reports ML202. SET LOCAL outside a transaction reports ML200 even when
the policy is off because the setting has no effect. SET and SET LOCAL are
transactional; rollback restores earlier values, commit discards local settings,
and release retains current settings while removing the savepoint and its
descendants. Duplicate savepoint names select the most recent surviving entry.
Unknown SQL taints both transaction and timeout state.

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
