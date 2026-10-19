# Validation and limits

Validated toolchain: moon 0.1.20261012, moonc v0.10.15+943464bfa,
moonrun 0.1.20261012, obtained from the official stable distribution.

Local evidence on 2026-10-19:

| Check | Observed result |
| --- | --- |
| Formatting and regenerated interface | Checked; generated API includes explicit initial-transaction and opt-in timeout flags |
| Strict compilation | Passed for wasm, wasm-gc, js, native |
| Unit and documentation tests | 23 passed on each of wasm, wasm-gc, js, and Linux native |
| File CLI end-to-end suite | Passed on wasm, wasm-gc, js, and Linux native |
| Windows native execution | Unavailable: MSVC/Windows SDK not installed |
| PostgreSQL 18 oracle script | Strict compilation passed; database execution not performed locally |
| GitHub Actions | Not run locally; requires an authorized push and a remote run |

Linux execution uses WSL Ubuntu 22.04. macOS behavior is covered by the supplied
CI matrix but has not been executed locally. These results do not imply broad
PostgreSQL syntax compatibility, measured lock predictions or ecosystem uniqueness.

The library has no FFI. The file adapter uses moonbitlang/x filesystem and
process-exit APIs and core's strict UTF-8 decoder. Node's two-element executable
prefix differs from Wasm/native; the adapter selects it per target.

## Reproduce without a database

Run the commands in README. `scripts/e2e.mbtx <target>` checks real upstream
fixtures, authored multi-statement workflows, report determinism, JSON round
trips and a deliberately malformed UTF-8 file. Expected findings and incomplete
reports are successful test outcomes; the CLI itself still returns 1 or 2.
The script dependency moonbitlang/async 0.22.5 is Apache-2.0 and tooling-only.

The River production fixture deliberately returns incomplete: its function and
ALTER statement are outside scope. It must never produce a clean whole-file
review merely because the index operations were recognized. Source and licenses
are recorded in THIRD_PARTY.md. Fixtures are not automatically executed.

## PostgreSQL execution oracle

Use a **disposable** PostgreSQL 18 database named `migrationlens_test`, with
psql on PATH. Set normal PGHOST/PGPORT/PGUSER/PGPASSWORD variables, PGDATABASE
to `migrationlens_test`, and MIGRATIONLENS_DISPOSABLE_DB to `1`, then run:

```text
moon run scripts/postgres_probe.mbtx
```

The probe creates and drops only its `migrationlens_probe` table and indexes.
It refuses to run without the explicit test-database markers and checks major
version 18. A failed probe can leave its table in the disposable database;
recreate that database before retrying. Never point it at an application DB.

The probe checks actual SQLSTATE 25001 for explicit and implicit transaction
conflicts, including COMMIT inside a multi-statement message. It also checks
separate dispatch and actual timeout values after SET LOCAL, commit, rollback
and rollback to savepoint. These correspond to transaction_test.mbt and
timeout_test.mbt. It is an oracle for these semantics, not a complete PostgreSQL
compatibility or concurrency/locking test.

## Evidence policy

Formatting, generated interfaces, strict compilation and runtime tests are
separate checks. Windows native runtime needs MSVC Build Tools/Windows SDK;
native typechecking alone is not recorded as native execution. Linux native
runtime is tested separately using the same stable compiler version.
Remote CI results require a pushed commit and an actual Actions run; a supplied
workflow does not establish success. Local PostgreSQL probe execution is also
reported separately from compiling the probe.
