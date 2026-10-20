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

Initial-session timeout regressions cover unknown/zero/positive/maximum/negative
values, policy opt-in, reset-to-unknown, rollback/commit/savepoint/chain behavior,
unknown SQL/dispatch, external rollback baselines, independent batch initialization
and retained JSON/SARIF context. Invalid empty-batch configuration cannot return
exit 0. Manifest tests enforce the new optional top-level integer's range/type
and duplicate-key rejection. CLI suites exercise initial values, repeated/invalid
options and the session manifest. A new database probe demonstrates differing
current/pre-transaction values across external rollback; execution is pending.
For this follow-up, 63 unit/documentation tests passed on all four targets with
the October 16 toolchain, including actual Linux native tests. Strict all-target
compilation and formatting/interface checks passed. Single-file/batch CLI suites
passed on Wasm, Wasm-GC, JavaScript and Linux native; the session-bearing SARIF and
prior single-file/batch samples passed the official schema locally. Windows
native execution and the added PostgreSQL probes remain unexecuted locally;
remote CI requires a separately authorized push and an actual run.

REINDEX option tests cover enabled/disabled boolean spellings, option ordering,
tablespace review, timeout policy, retained source, duplicate/unknown clauses
and malformed lists. `fixtures/reindex-options.sql` exercises ML111 in the CLI.
Additional PostgreSQL probes check parenthesized concurrent rebuilding, explicit
FALSE inside a transaction and SQLSTATE 25001 for enabled concurrent rebuilding;
they are compiled only until database execution is explicitly reported.

The multi-file extension tests input ordering, duplicate path labels, isolation
of transaction/timeout state, continued review after incomplete SQL, maximum
exit-code aggregation, deterministic JSON, separate SARIF runs and rejection of
partial SARIF conversion. Manifest tests reject unknown fields, duplicate decoded
keys, invalid versions/types/policies/paths/Unicode and over-limit input, while
accepting the 1,000-entry boundary. CLI tests cover all output formats, real
upstream SQL, missing/invalid-UTF-8 files and recovery after bad input. The sample
manifest is `fixtures/review-manifest.json`; its SARIF output is written to
`_build/sarif-batch.json` by the e2e suite for optional schema validation.

Manifest duplicate-key rejection requires the October 16 core API used by CI.
Local Linux validation now uses the same October 16 compiler/core, installed in
an isolated toolchain directory, replacing the earlier October 12 runtime checks
for this follow-up. Historical results above remain recorded with their versions.
The current follow-up passed 54 unit/documentation tests on Wasm, Wasm-GC,
JavaScript and Linux native with that same compiler/core. Strict checks passed
for all targets, and all four single-file/batch CLI suites passed, including
actual Linux native execution with October 16.
The emitted three-run batch SARIF and all single-file SARIF samples passed the
official schema locally. Added PostgreSQL rename probes are compiled only;
no new remote CI run or Windows native execution is claimed.

Index rename regressions cover the create/drop/rename replacement workflow,
quoted/qualified names, IF EXISTS, transaction-local timeout, source ranges,
deterministic reports and unsupported trailing clauses. The database probe
adds a transactional rename and restoration of a disposable index; these added
database cases are strictly compiled only, with execution pending.

SARIF regression coverage includes clean, covered and incomplete reports,
duplicate rule descriptors without merging results, retained source/severity/
message/help/spans, deterministic JSON round trips, UTF-8 URI encoding, Windows
separators, rejected paths, CRLF/CR/LF, surrogate-pair boundaries, invalid public
metadata and zero-width EOF spans. The e2e suite checks CLI output formats and
exit codes and writes `_build/sarif-0.json`, `sarif-1.json` and `sarif-2.json`.
All three emitted cases passed the official OASIS SARIF 2.1.0 errata01 JSON
Schema locally on 2026-10-20 with Python jsonschema 3.2.0. This establishes
schema conformance of those samples, not hosted service upload compatibility.

Optional schema reproduction (requires curl and Python jsonschema installed):

```text
moon run scripts/e2e.mbtx wasm
curl -fL https://raw.githubusercontent.com/oasis-tcs/sarif-spec/main/sarif-2.1/schema/sarif-schema-2.1.0.json -o _build/sarif-schema.json
python -m jsonschema -i _build/sarif-0.json -i _build/sarif-1.json -i _build/sarif-2.json _build/sarif-schema.json
```

The schema download is an external validation resource, not a runtime dependency
or vendored file. The standard portable CI suite now exercises the SARIF CLI
cases; the optional external schema command is separate from that suite.

The REINDEX/SARIF follow-up has 45 passing unit/documentation tests on Wasm,
Wasm-GC and JavaScript using October 16, and Linux native using October 12.
All four CLI suites passed (Linux native uses October 12), including existing
JSON/text behavior, new SARIF output and malformed input. Strict checks passed for all four targets
with October 16. Windows native execution and new PostgreSQL probes remain
unexecuted locally; no new remote CI result is claimed before pushing.

REINDEX INDEX tests cover ordinary/concurrent operations, qualified and escaped
names, implicit/explicit/caller transactions, timeout maxima, preserved source,
determinism and unsupported options/scopes. The PostgreSQL probe adds actual
ordinary/concurrent rebuilds and expected SQLSTATE 25001 conflicts. These new
database cases are strictly compiled only; execution remains pending.

The bounded-timeout extension retains integer milliseconds through all scope
snapshots and adds inclusive maximum, overflow, disabled/default, rollback,
chain, invalid-policy and review-isolation regressions. The optional library
argument is `max_lock_timeout_ms`; CLI invalid/repeated values are rejected
before reading the file. `fixtures/timeout-limit.sql` demonstrates the same
input failing a 2000ms limit and passing a 10000ms limit.

Local checks for the three follow-up capabilities (2026-10-19): 34 unit and
documentation tests passed on Wasm, Wasm-GC and JavaScript with the October 16
toolchain, and on Linux native with the October 12 toolchain. Strict compilation
passed for all four targets with October 16; formatting and generated interfaces
were checked with that compiler. The expanded CLI suites passed on Wasm,
Wasm-GC and JavaScript (October 16), and Linux native (October 12).
Windows native execution remains unavailable. New
PostgreSQL oracle cases were strictly compiled but have not run against a local
database or in remote CI. These results do not supersede the toolchain/OS limits
recorded above.

DROP INDEX regressions cover qualified/quoted names (including embedded comma,
semicolon and Unicode), ordinary name lists, concurrent multi-name/CASCADE
errors, malformed identifiers and unsupported trailing tokens. The authored
`fixtures/drop-indexes.sql` exercises ML107 in the CLI suite. Additional oracle
cases expect SQLSTATE 0A000 for both forbidden concurrent combinations and
execute qualified RESTRICT and ordinary multi-name drops. These new database
cases are pending execution; no new remote run is claimed before a push.

The transaction-chain extension adds unit cases for END/ABORT aliases, every
WORK/TRANSACTION suffix, AND NO CHAIN, fresh timeout baselines, cleared savepoints,
caller transactions and invalid idle/implicit chaining. Its authored fixture is
`fixtures/chained-transaction.sql`. The oracle now checks chain timeout values
and SQLSTATE 25P01/25001. These added database cases have not yet run locally or
in remote CI; compiling the probe does not establish server agreement.

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
