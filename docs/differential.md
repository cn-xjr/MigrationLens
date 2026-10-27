# Seeded PostgreSQL differential testing

The generated oracle compares transaction and effective-timeout findings with an
actual PostgreSQL 18 process. It supplements the existing hand-authored probes;
it does not replace them or claim exhaustive SQL/locking compatibility.

Without a database, inspect a deterministic plan:

```text
moon run cmd/scenarios -- 1 2 8
moon run scripts/differential.mbtx --self-test
```

The first command emits version-1 JSON with generator version, tool/rule origin,
seeds, original SQL, dispatch commands and both static reports. The second checks
the verdict logic's success/failure boundaries, including malformed observations,
wrong SQLSTATEs and replay metadata, without connecting to a database.

## Execute the real oracle

Use the same explicit disposable PostgreSQL 18 setup as [validation.md](validation.md):
PGDATABASE=migrationlens_test, MIGRATIONLENS_DISPOSABLE_DB=1, usual PG connection
variables and psql on PATH. Then run:

```text
moon run scripts/differential.mbtx
moon run scripts/differential.mbtx 2147483646 2 128
```

Defaults are seed 20261028, 32 cases, 40 generated steps. Bounds are seed
1..2147483646, count 1..256, steps 0..128. Seeds increment with wraparound.
Every case runs in both separate-statement and whole-file simple-query dispatch.
CI executes 68 real server comparisons: 32 x 2 plus 2 x 2 boundary-seed cases.

The integer-only Park-Miller recurrence is pinned as generator version 1. The
generator tracks only enough transaction/savepoint structure to produce valid
commands. It does not compute timeout state or expected timeout values. Inputs
cover SESSION/LOCAL SET, transaction starts/ends/chains, duplicate savepoint
names, ROLLBACK TO and RELEASE. Values exercise disabled, inclusive policy bounds
and excessive finite settings. RESET, unknown external transactions, invalid SQL,
catalog failures and concurrent workloads are outside this generated subset.

Each server connection starts with known lock_timeout=0, matching the analyzer's
initial fact, and statement_timeout=5s bounds each server command. A read-only
`pg_settings` query observes the effective lock_timeout value and its unit just
before a concurrent-index sentinel. The script checks that observed milliseconds
match the static ML201/ML205/no-timeout-warning classification. It independently
checks whether the sentinel actually succeeds or fails with SQLSTATE 25001.
Other server errors and missing/ambiguous observations fail the oracle.
Only a terminal `ERROR: 25001` record with a normal psql SQL-error exit is
accepted as a conflict. Earlier WARNING records cannot hide a different terminal
error or a crashed process. This output parser uses the English severity labels
of the CI server; other/localized diagnostic formats fail closed.

The observer does not enter the reviewed SQL. For simple dispatch it is inserted
into the same multi-statement message, whose input already contains multiple
statements; it does not create an otherwise absent implicit transaction. For
separate dispatch it is its own command in the same connection. This checks
effective state and transaction restrictions, not actual waiting duration.

The script creates only its own `migrationlens_diff_probe` table and generated
indexes. It refuses an already-existing table rather than deleting it. After
successful setup it attempts cleanup on both success and failure; if cleanup
fails, recreate the disposable database before retrying. Run one oracle at a time
per disposable database. Connection credentials are never printed or archived.

## Preserve and replay a counterexample

A semantic mismatch saves `_build/differential/seed-<seed>-<mode>.json`, including
generator/tool/rule identity, complete SQL/static reports, server status/output,
the mismatch reason and replay parameters. An existing saved failure is retained.
CI uploads these files on failure as a downloadable artifact.

```text
moon run scripts/differential.mbtx --replay _build/differential/seed-1-separate.json
```

Replay regenerates exactly one seeded scenario and checks byte-identical SQL
before opening the database. It runs current analysis against the live oracle;
it does not execute SQL taken from an unvalidated saved payload. A generator
version mismatch or altered SQL is rejected. Keep a reviewed counterexample with
its regression test when fixing the underlying rule, rather than accepting a new
expected result automatically.

Sources: PostgreSQL 18 [pg_settings](https://www.postgresql.org/docs/18/view-pg-settings.html)
and [simple-query protocol](https://www.postgresql.org/docs/18/protocol-flow.html#PROTOCOL-FLOW-MULTI-STATEMENT).
The generator, runner and tests are authored here under Apache-2.0; no upstream
generator, parser or test implementation is copied.
