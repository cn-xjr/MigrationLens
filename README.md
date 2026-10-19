# MigrationLens

Offline PostgreSQL 18 index migration review for MoonBit tool authors.
Reports potentially blocking ordinary index operations and concurrent index
operations conflicting with a declared existing transaction. Source is retained
verbatim. Unsupported SQL is explicitly incomplete, never silently discarded.

Currently covers CREATE INDEX, DROP INDEX, BEGIN/START TRANSACTION and
COMMIT/ROLLBACK, including WORK/TRANSACTION suffixes. Execution modes distinguish
separate dispatch, a single simple-query message and an existing transaction.
Unknown context and unsupported statements produce incomplete reports.
Timeout and savepoint analysis are planned, not implemented yet.
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

Import `cn-xjr/migration_lens`. Public API: `review_sql`, `Execution`, `Report`,
`Diagnostic`, `Severity`, `Span`. Reports provide `exit_code`, `to_text` and
versioned deterministic `to_json`. Spans use half-open UTF-16 code-unit offsets;
text positions are one-based UTF-16 columns and lines.

Exit codes: 0 = no findings within the documented rule set; 1 = findings on
covered input; 2 = incomplete analysis or CLI input failure. CI should reject
both 1 and 2. Unknown execution is never assumed to be autocommit.

Lexical input supports standard strings without backslashes, quoted identifiers,
line/nested block comments and dollar-quoted bodies (which remain opaque).
psql commands, COPY data streams, templates and dynamic SQL are unsupported.
Valid PostgreSQL outside the pinned parser subset also returns incomplete.

## Development

```text
moon fmt
moon info
moon check --target all --deny-warn
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon test --target native --deny-warn
```

CI covers Linux, macOS and Windows; native runtime tests run on Linux/macOS.
A workflow definition does not establish a passed remote run. See
[design](docs/design.md) for scenarios, evidence and capability roadmap.

Apache-2.0; third-party fixtures and dependencies retain their own licenses.
