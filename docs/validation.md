# Validation and limits

Initial local validation used moon 0.1.20261012, moonc v0.10.15+943464bfa,
moonrun 0.1.20261012. CI now selects the stable `0.10.16+b1a0e846e` release
for both binaries and core; generated interfaces are refreshed with that
release. Distribution: <https://cli.moonbitlang.com/version.json>.

Initial evidence on 2026-10-19 (October 12 local toolchain):

| Check | Observed result |
| --- | --- |
| Formatting and regenerated interface | Checked; generated API includes explicit initial-transaction and opt-in timeout flags |
| Strict compilation | Passed for wasm, wasm-gc, js, native |
| Unit and documentation tests | 23 passed on each of wasm, wasm-gc, js, and Linux native |
| File CLI end-to-end suite | Passed on wasm, wasm-gc, js, and Linux native |
| Windows native execution | Unavailable: MSVC/Windows SDK not installed |
| PostgreSQL 18 oracle script | Strict compilation passed; database execution not performed locally |
| GitHub Actions | Initial portable matrix passed; the repaired PostgreSQL job at `2cb75ba` also passed on PostgreSQL 18 |

Linux execution uses WSL Ubuntu 22.04. macOS behavior is covered by the supplied
CI matrix and has passed remotely, but has not been executed locally. These results do not imply broad
PostgreSQL syntax compatibility, measured lock predictions or ecosystem uniqueness.

After the CI fixes, the October 16 stable toolchain passed strict checks for
all four targets and 24 local tests on Wasm, Wasm-GC and JavaScript, plus the
Wasm/JS CLI suites. The added regression also passed Linux native on the
October 12 toolchain; CI exercises native with the selected October 16 release.

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

The probe names each stage before invoking psql and includes that name, exit
code and stderr if it fails. It prints the numeric server version, never the
connection environment or password. Additional server-backed cases verify
session SET overriding SET LOCAL, session settings surviving COMMIT, same-name
savepoint shadowing, RELEASE retaining settings/removing descendants, ROLLBACK
TO removing descendants, quoted-name case sensitivity and caller transactions
combined with simple-query dispatch. Missing savepoints require SQLSTATE 3B001;
concurrent-index transaction conflicts require 25001, not merely any failure.

## Evidence policy

Formatting, generated interfaces, strict compilation and runtime tests are
separate checks. Windows native runtime needs MSVC Build Tools/Windows SDK;
native typechecking alone is not recorded as native execution. Linux native
runtime is tested separately using the same stable compiler version.
Remote CI results require a pushed commit and an actual Actions run; a supplied
workflow does not establish success. Local PostgreSQL probe execution is also
reported separately from compiling the probe.

## Fresh-runner dependency bootstrap

The first remote run at `304a6c7` passed all three portable jobs, but the
PostgreSQL job stopped before connecting to its database: the new runner had
no registry index for the standalone script's `moonbitlang/async` dependency.
Its log reported `Failed to resolve the module dependency graph`, not a
PostgreSQL assertion failure. The same failure was reproduced with an empty
MOON_HOME registry. Every job using standalone scripts must run `moon update`
after installing the toolchain. The PostgreSQL job also strictly checks the
probe before executing it so dependency/compile failures are a separate step.

The next run at `2cb75ba` passed the PostgreSQL 18 oracle but detected a second,
independent issue: floating `latest` had advanced to the October 16 compiler.
That compiler prints explicit `Int32` in generated interfaces where the earlier
compiler printed `Int`, so the deliberate interface-drift check correctly
failed. CI now selects a known compiler/core release together. Updating that
selection requires rerunning `moon info`, reviewing the interface and testing
all targets. Official download URLs are retained for a limited time, so the
pin must be refreshed during toolchain maintenance rather than left indefinitely.

Windows fresh checkouts with core.autocrlf enabled exposed an additional
formatter-check failure: the formatter compared CRLF source against LF output
through a Windows extended path that Git could not open. This was reproduced
in a disposable fresh clone. `.gitattributes` now checks out all text as LF,
preserving the original SQL fixture bytes and the canonical source format on
every runner. The format and interface checks remain enabled.
