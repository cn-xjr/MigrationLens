# MigrationLens

Offline PostgreSQL 18 index migration review for MoonBit tool authors.
Reports potentially blocking ordinary index operations and concurrent index
operations conflicting with a declared existing transaction. Source is retained
verbatim. Unsupported SQL is explicitly incomplete, never silently discarded.

Currently covers CREATE INDEX, DROP INDEX, BEGIN/START TRANSACTION and
COMMIT/ROLLBACK, including WORK/TRANSACTION suffixes. Execution modes distinguish
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
