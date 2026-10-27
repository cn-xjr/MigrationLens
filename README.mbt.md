# MigrationLens

[![CI](https://github.com/cn-xjr/MigrationLens/actions/workflows/ci.yml/badge.svg)](https://github.com/cn-xjr/MigrationLens/actions/workflows/ci.yml)

Offline PostgreSQL 18 migration review for MoonBit migration-runner and CI tool
authors. MigrationLens combines SQL with the runner's dispatch, transaction and
timeout context, then reports actionable findings with original source ranges.
Unsupported input stays visible and makes the review incomplete.

The source is Apache-2.0. The library coordinate is
[`cn-xjr/migration_lens@0.1.0`](https://mooncakes.io/docs/cn-xjr/migration_lens).

From your own MoonBit module, add the dependency:

```text
moon add cn-xjr/migration_lens@0.1.0
```

Then import `"cn-xjr/migration_lens" @migration_lens` in your `moon.pkg`.
See [the consumer guide](docs/consumer.md) for the complete integration and
[validation evidence](docs/validation.md) for observed release checks.

## Try a real migration

Use MoonBit stable `0.10.16+b1a0e846e` (the release pinned in CI). JavaScript
execution also needs Node.js; native execution needs a C compiler.

```text
git clone https://github.com/cn-xjr/MigrationLens.git
cd MigrationLens
moon update
moon run cmd/main -- fixtures/postgres-migrations-concurrent.sql separate
```

This unchanged upstream migration-runner test fixture returns a complete review
and exit **0**. Its source and MIT notice are in [THIRD_PARTY.md](THIRD_PARTY.md).
The CLI reads files and prints a report; it does not execute the SQL.

```text
moon run cmd/main -- fixtures/batch-indexes.sql simple --json
moon run cmd/main -- fixtures/river-006-bulk-unique.sql separate
moon run scripts/e2e.mbtx wasm
```

The first command returns **1**: two concurrent index statements in one
simple-query message conflict with its implicit transaction. The second returns
**2**: a real River migration contains unsupported function/ALTER SQL, so its
covered index findings cannot make the whole file pass. The final command checks
these expected exits, saved reports, baselines and malformed input, then exits
**0** when the complete workflow passes. No database or private service is needed.

## Integrate the library

Supply the runner's actual dispatch behavior; disabling its explicit transaction
wrapper does not establish that statements are sent separately.

```mbt check
///|
test "quickstart distinguishes runner dispatch" {
  let sql = "SET lock_timeout=100; CREATE INDEX CONCURRENTLY orders_idx ON orders(id);"
  let separate = @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
  )
  let whole_file = @migration_lens.review_sql(
    sql,
    execution=SimpleQuery,
    max_lock_timeout_ms=100,
  )
  assert_eq(separate.exit_code(), 0)
  assert_eq(whole_file.exit_code(), 1)
  assert_eq(whole_file.diagnostics[0].code, "ML101")
}
```

`ExistingTransaction` means separate dispatch inside a caller's transaction.
For whole-file dispatch inside that transaction, use `SimpleQuery` together with
`initial_transaction=true`. `Unknown` cannot produce a complete review.
Timeout policy is opt-in: `require_lock_timeout` requires an effective finite
value; `max_lock_timeout_ms` adds an inclusive upper bound. A caller-assured
`initial_lock_timeout_ms` supplies a connection's session setting at entry.

For CI, persist a report and compare it with a trusted baseline from the same
project/rule version. Batch archives retain per-file execution and policy facts.
For automatic project/version/context compatibility checks, use the new
[version-2 review archive](docs/archive.mbt.md). V1 APIs below remain compatible.

```mbt check
///|
test "quickstart restores a batch and gates new findings" {
  let batch = @migration_lens.review_migrations(
    [
      @migration_lens.Migration::new(
        "migrations/001.sql",
        "DROP INDEX old_idx;",
        execution=SeparateStatements,
      ),
    ][:],
  )
  let restored = @migration_lens.BatchReport::parse_json(
    batch.to_json().stringify(),
  ).unwrap()
  assert_eq(batch.exit_code(), 1)
  assert_eq(
    @migration_lens.compare_batches(batch, restored).unwrap().exit_code(),
    0,
  )
  assert_true(restored.to_sarif() is Ok(_))
}
```

A baseline gate accepts retained findings; the full current report still has
its own absolute exit code. Invalid or incomplete comparison input is rejected.
No baseline is updated automatically. Single-report baselines additionally need
the caller to verify matching execution/policy context.

Run `moon run scripts/consumer.mbtx wasm` to compile, test and execute a separate
module against a freshly packaged local ZIP. It checks source/licenses and
cache exclusion, then resolves the library through a local workspace. It does
not upload a package. See [downstream integration](docs/consumer.md) for all four
targets and adapting the example to your tool.

## Supported review boundary

| Area | Implemented workflow |
| --- | --- |
| Index rollout | CREATE/DROP INDEX, single-index REINDEX, rename and SET TABLESPACE |
| Execution state | Explicit/simple-query transactions, chaining, savepoints, rollback and release |
| Lock waiting | Session/local lock_timeout, resets, caller entry facts and maximum policy |
| Maintenance | Explicit table locks, ANALYZE, VACUUM, CLUSTER and materialized-view refresh |
| Staged constraints | Foreign keys with NOT VALID, validation, UNIQUE/PRIMARY KEY USING INDEX, SET NOT NULL |
| Tool integration | Text, v1/v2 JSON archives, SARIF 2.1.0, batch review and trusted baseline comparison |

Each SQL family has a closed supported grammar, documented in the
[detailed reference](docs/reference.mbt.md). Other DDL/DML, templates, psql
commands, COPY data and unsupported clauses produce incomplete diagnostics.
Input is bounded to 1,000,000 UTF-16 code units; file input must be valid UTF-8.
SQL source is retained verbatim; no SQL rewrite or lossy reserialization occurs.

`complete=true` means coverage of this rule set. Catalog facts, historical data,
permissions, relation kinds and concurrent workload still require verification.
MigrationLens does not certify deployment success or predict measured lock time.

## Commands and documentation

All commands run from the checkout root and return 0 (no findings), 1 (covered
findings), or 2 (incomplete/invalid input). Baseline commands return 1 only for
new findings; their full reports preserve accepted findings.

| Entry point | Task |
| --- | --- |
| `cmd/main` | Review a UTF-8 SQL file with explicit execution mode |
| `cmd/ci` | Save full artifacts, check provenance and apply an optional baseline gate |
| `cmd/batch` | Review a strict JSON manifest with independent per-file context |
| `cmd/report`, `cmd/report_batch` | Restore saved archives and render text/JSON/SARIF |
| `cmd/compare`, `cmd/compare_batch` | Compare trusted complete baseline/current archives |

- [Detailed syntax, flags, formats and examples](docs/reference.mbt.md)
- [Separate-module consumer and packaging check](docs/consumer.md)
- [Complete CI workflow and downstream Actions example](docs/ci.md)
- [Design, differentiation and scope](docs/design.md)
- [Current validation matrix and reproduction](docs/validation.md)
- [Seeded PostgreSQL differential tests and failure replay](docs/differential.md)
- [Pinned SARIF schema validation and GitHub profile](docs/sarif-validation.md)
- [Maintainer handoff](docs/maintaining.md) and [changelog](CHANGELOG.md)
- [Generated public API](pkg.generated.mbti) and [sources/licenses](THIRD_PARTY.md)

## Develop and verify

```text
moon fmt --check
moon info
git diff --exit-code -- pkg.generated.mbti cmd docs/pkg.generated.mbti
moon check --target all --deny-warn
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon test --target native --deny-warn
```

CI executes portable tests, CLI and packaged-consumer workflows on Linux,
macOS and Windows; Linux/macOS also execute native workflows. A separate
PostgreSQL 18 job checks actual transaction, timeout and lock semantics in a
disposable database. Windows native runtime support has not been verified.
See the validation matrix for observed results and prerequisites.
