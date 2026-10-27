# Historical validation notes

These notes record evidence at the time of each development step. References to
pending execution are historical, not the current delivery status. Consult
[the current validation matrix](validation.md) for the maintained evidence.

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

2026-10-26 packaged downstream validation: `scripts/consumer.mbtx` passed on
Wasm, Wasm-GC, JavaScript and actual Linux native. Each target builds a local ZIP,
checks its delivery set/licenses and cache exclusion, extracts it into a fresh
workspace, then checks and runs three consumer tests and its executable using
only the public dependency. Source/archive checks and all 163 library/doc tests
remain passing; public interfaces are unchanged. CI now explicitly builds the
three portable targets and repeats the consumer workflow on all supported runner
targets. The local Linux toolchain's existing packaging/formatting helpers needed
their executable bits restored; WSL also needed the documented unzip prerequisite.
No package upload, registry publication or release tag was performed.
The preceding CR-comment fix passed Linux/macOS/Windows and PostgreSQL 18 in
[run 40349695555](https://github.com/cn-xjr/MigrationLens/actions/runs/40349695555).

2026-10-26 correctness audit: reproduced three failing regressions where a CR
line ending left following SQL hidden inside a line comment. Fixed comment
termination at CR/LF and recognized vertical-tab whitespace per PostgreSQL's
scanner. All 163 tests passed on Wasm, Wasm-GC, JavaScript and actual Linux
native; strict all-target compilation, generated interfaces and script checks
passed. The full Wasm CLI suite exercised an actual CR-only UTF-8 file. The
RELEASE fixture ran as a native process with expected ML201/exit 1. RELEASE
state restoration was inspected and already correct; four new tests strengthen
session/local changes, inclusive policy bounds, nested release and outer rollback.
No RELEASE implementation fix is claimed. New PostgreSQL probes compile locally
and await this commit's CI. No package registry publication was performed.

SET NOT NULL: all 155 unit/documentation tests passed on Wasm, Wasm-GC,
JavaScript and actual Linux native with October 16 stable. Full portable CLI
suites passed; the documented proof-validation/promotion/index-attachment
fixture also ran through the Linux native CLI with expected exit 1 and six
warnings. Formatting, strict all-target compilation, script checks and interface
regeneration passed with no public API changes. All seven SARIF samples passed
the external OASIS 2.1.0 schema. Tests cover 1..32 complete action lists, malformed
boundaries, CHECK-removal/mixed-command rejection, timeout/savepoint state,
dispatch distinctions, preserved uncertainty, UTF-16 spans and archive round trips.
New PostgreSQL probes compile locally and await CI for actual historical-NULL
failure, data repair, retained strong lock and later write enforcement. These
probes do not measure scan avoidance. No local database or Windows native run
is claimed. Foreign-key commit `cb8ce9d` passed all four CI jobs in
[run 39425758936](https://github.com/cn-xjr/MigrationLens/actions/runs/39425758936).

Foreign-key installation: all 148 unit/documentation tests passed on Wasm,
Wasm-GC, JavaScript and actual Linux native using October 16 stable. The full
Wasm CLI suite and the documented install/validate/index fixture on all four
CLI targets passed. Strict all-target and script checks, formatting and
generated interfaces passed; public API unchanged. Tests exercise historical
validation, all five action kinds on DELETE/UPDATE, MATCH, explicit timing,
1..24 quoted column lists, rejected mixed/unrepresented clauses, timeout state,
downstream uncertainty, spans, deterministic reports and JSON archive round trips.
The new PostgreSQL orphan/repair/cascade and dual-lock probes compile locally;
database execution awaits CI. Index attachment commit `87a87ed` passed all
four jobs, including actual PostgreSQL 18 probes, in
[run 39425194381](https://github.com/cn-xjr/MigrationLens/actions/runs/39425194381).

Index-backed constraint attachment: 141 unit/documentation tests passed on
Wasm, Wasm-GC, JavaScript and actual Linux native with October 16 stable.
The complete Wasm CLI suite and the documented attachment fixture on all four
CLI targets passed (fixture exit 1 with ML190/ML191). Formatting, strict
all-target compilation, script checks and interface regeneration passed;
the public API is unchanged. Tests cover UNIQUE/PRIMARY KEY, explicit timing
attributes, mixed-action rejection, quoted names, dispatch, savepoint/timeout
state, source spans, deterministic output and report archive round trips.
New PostgreSQL probes compile locally and await CI execution for actual locks,
index renaming/ownership and primary-key nullability/timing attributes.
The preceding constraint-validation commit `5227201` passed all four jobs in
[run 39423857814](https://github.com/cn-xjr/MigrationLens/actions/runs/39423857814).
No local PostgreSQL or Windows native run is claimed.

Constraint validation (October 16 stable toolchain): all 136 unit/documentation
tests passed on Wasm, Wasm-GC, JavaScript and actual Linux native. Strict
all-target compilation, formatting, script checks and interface regeneration
passed with no public API changes. Full CLI suites passed on all four targets,
including actual Linux native processes. All seven emitted SARIF samples passed
the external OASIS 2.1.0 JSON schema.
Tests cover validation-only action lists (1..32), quoted delimiters, scope
markers, malformed/mixed actions, transaction and savepoint timeout preservation,
unknown-state recovery, exact source spans, deterministic output and archive
round trips. New PostgreSQL probes compile locally and check real rows, CHECK
and NOT NULL validation flags, maintenance/reference lock modes, historical
data violations and already-valid constraints. Database execution awaits this
commit's remote CI; no local database or Windows native run is claimed.
Refresh commit `df845b3` passed Linux/macOS/Windows and PostgreSQL 18 jobs in
[run 39422467250](https://github.com/cn-xjr/MigrationLens/actions/runs/39422467250).

Materialized-view refresh: 129 unit/documentation tests passed on all four
targets with the October 16 toolchain; all portable CLI suites passed, and the
documented refresh fixture ran through the Linux native CLI with expected exit
1 and ML170/ML171/ML140. Strict all-target compilation, generated interfaces
and script checks passed. Regression coverage includes ordinary/concurrent
refresh in transactions, NO DATA, incompatible flags, timeout rollback,
malformed input, uncertainty preservation, Unicode spans and archive round trips.
PostgreSQL probes check both actual lock modes, readability/population state,
missing UNIQUE indexes and invalid combinations; conflicting-option probes use
a populated view so the earlier population check does not mask the expected
42601 error. These new probes compile locally and await remote execution.
CLUSTER commit `437840c` passed Linux/macOS/Windows and PostgreSQL 18 jobs in
[run 39421880220](https://github.com/cn-xjr/MigrationLens/actions/runs/39421880220).

CLUSTER validation (October 16 stable toolchain): all 122 unit/documentation
tests passed on Wasm, Wasm-GC, JavaScript and actual Linux native. Strict
all-target compilation, formatting and interface regeneration passed with no
public API changes. Portable CLI suites exercise targeted reordering followed
by ANALYZE; the documented fixture also ran as a native process with expected
exit 1 and ML160/ML163/ML140. Tests cover known/unknown transaction blocks,
database-wide scope, malformed options/names, downstream uncertainty, timeout
rollback, UTF-16 spans, deterministic output and typed archive round trips.
New PostgreSQL probes compile locally; execution is delegated to remote CI.
The previous VACUUM commit passed all four jobs in
[run 39399780004](https://github.com/cn-xjr/MigrationLens/actions/runs/39399780004).
No local PostgreSQL or Windows native execution is claimed.

VACUUM tests cover separate/simple/explicit/external/unknown transaction state,
all 16 legacy-option subsets, effective FULL/TRUNCATE/INDEX_CLEANUP settings,
SKIP_LOCKED timeout limits, database-wide scope, 1..16 target lists, unsupported
options, malformed input, recovery, UTF-16 spans, deterministic JSON and typed
single/batch archive round trips. READ ONLY diagnostic wording was corrected:
DDL restrictions are not limited to non-temporary relations. All 117 unit and
documentation tests passed on Wasm, Wasm-GC, JavaScript and actual Linux native
with October 16. Full CLI suites passed on all four targets, including native
process execution. Formatting, strict all-target and script checks, generated
interfaces and all seven external SARIF schema samples passed. The public API
is unchanged; new SQL warnings are visible through the existing report types.
New VACUUM PostgreSQL probes are compiled locally; database execution remains
pending this commit's remote CI. No local database or Windows native run is
claimed. The previous ANALYZE commit `41a9df5` passed all four jobs in
[Actions run 39398733522](https://github.com/cn-xjr/MigrationLens/actions/runs/39398733522),
including the actual ANALYZE column/lock probes against PostgreSQL 18.

ANALYZE tests cover relation/column lists, ONLY/inheritance markers, quoted
names, boolean spellings, database-wide scope, SKIP_LOCKED with timeout checks,
scoped/savepoint state, malformed/unknown clauses, recovery, source spans,
deterministic JSON, typed archives and SARIF. All 108 unit/documentation tests
passed on Wasm, Wasm-GC, JavaScript and Linux native with October 16. Strict
all-target checks, script checks, formatting and generated interfaces passed.
The documented post-index CLI fixture ran on all four targets; server lock
probes are compiled locally and require the new CI run for execution evidence.
The preceding transaction-mode commit `96dae2e` passed all four jobs in
[Actions run 39398162138](https://github.com/cn-xjr/MigrationLens/actions/runs/39398162138),
including actual PostgreSQL characteristic and SQLSTATE checks.

Transaction-mode validation covers 32 start/isolation/separator combinations,
mode reordering, read-only/deferrable limitations, UTF-16 spans, JSON restoration,
SARIF, savepoint/chain timeout behavior, malformed/repeated modes and recovery.
All 102 unit/documentation tests passed on Wasm, Wasm-GC, JavaScript and actual
Linux native with the October 16 toolchain; strict all-target compilation,
formatting and interface regeneration passed. The documented mode-bearing CLI
fixture ran on all four targets with the expected findings. New PostgreSQL
characteristic/SQLSTATE probes are compiled locally; server execution requires
the pushed commit's CI. No public API changes are needed for this SQL extension.

Historical follow-up notes below record what had run at each milestone. The
subsequent pushed archive commit `a8931d3` passed all four jobs in
[Actions run 39375835782](https://github.com/cn-xjr/MigrationLens/actions/runs/39375835782):
Linux, macOS, Windows and the actual PostgreSQL 18 execution oracle. This
supersedes the earlier pending-remote status for those database probes; local
database execution and Windows native execution remain unclaimed.

Batch-baseline properties cover path reorder, added/removed files, repeated
path/context occurrences, each policy/initial-fact change, exact source-side
indices, deterministic JSON and conservation of all file/diagnostic counts.
Snapshots remain independent of input array mutation. Incomplete/invalid inputs
on either side fail atomically, including invalid empty batches. CLI suites use
saved real-fixture and authored-workflow archives, exercise text/JSON gates,
reject missing/non-UTF-8/incomplete inputs and recover with a valid comparison.
This capability passed 97 unit/documentation tests on each of Wasm, Wasm-GC,
JavaScript and Linux native using the October 16 compiler/core. Full CLI suites
passed on all four targets, including actual Linux native processes. Strict
all-target compilation, formatting and generated interfaces passed. All seven
SARIF samples passed the external official schema. Remote results for this
capability require its own pushed commit and completed Actions run.

Batch archive regressions cover exact JSON/text round trips, duplicate paths,
all context fields, shared timeout facts, signed integer boundaries, incomplete
SQL and canonical invalid-policy reports. Unknown/duplicate fields, altered
aggregate exit codes, inconsistent repeated context, malformed spans/metadata,
and lossy numeric spellings are rejected. CLI checks restore 0/1/2 archives in
all formats, reject bad input and recover with a valid archive. The restored
multi-run example is `_build/sarif-restored-batch.json` for schema validation.
The archive extension passed 90 unit/documentation tests on each of Wasm,
Wasm-GC, JavaScript and Linux native with the October 16 toolchain. Strict
all-target compilation, formatting and interface checks passed. Full CLI suites
passed on all four targets, including actual Linux native execution; the added
batch SARIF sample passed the external official schema.

Single-index tablespace tests cover qualified/quoted names and destinations,
UTF-16 source spans, deterministic JSON and typed restoration, SARIF export,
transaction/savepoint timeout state, inclusive maxima, disabled/unknown values,
simple-query conflicts on subsequent concurrent operations, unsupported bulk
forms/clauses and recovery with an independent valid input. Existing rename
tests still run through the shared closed ALTER INDEX classifier. The CLI suite
reviews `fixtures/move-index.sql` under separate and simple dispatch.
An added PostgreSQL probe requests pg_default on an existing disposable index
and checks its actual ACCESS EXCLUSIVE lock. This is a no-copy placement case;
the new probe has only been compiled locally, not executed against a server.
The completed follow-up passed 85 unit/documentation tests on each of Wasm,
Wasm-GC, JavaScript and Linux native with the October 16 compiler/core. Strict
all-target compilation, formatting and interface checks passed; the public API
is unchanged by this SQL extension. Full CLI suites passed on all four targets,
including actual Linux native execution. All six generated SARIF samples passed
the external official schema. No new remote CI run or Windows native execution
is claimed.

Baseline comparisons check duplicate-count conservation in both directions,
stable source order, position-only movement, exact SQL/metadata changes,
invalid UTF-16 spans/Unicode, inconsistent and incomplete reports, deterministic
JSON, retained sources and snapshots independent of input array mutation.
The CLI suite compares a real upstream fixture against an authored added DROP
INDEX, retains existing findings, resolves removed findings and rejects malformed,
missing, non-UTF-8 and incomplete report inputs. Existing SARIF errors and output
are preserved while report validation is shared with the new library workflow.
This capability passed 81 unit/documentation tests on each of Wasm, Wasm-GC,
JavaScript and Linux native, with strict all-target compilation and format/API
checks on the October 16 toolchain. Full CLI suites passed on all four targets,
including actual native process execution. All six SARIF samples passed the
external official schema. No new remote CI run is claimed before a push.

Table-lock regressions cover all eight modes, default ACCESS EXCLUSIVE, relation
lists, ONLY/star markers, quoted Unicode names, UTF-16 spans, deterministic
reports, JSON restoration, SARIF export, invalid clauses and downstream unknown
state. They distinguish idle, existing, explicit, unknown and multi-statement
simple-query blocks, including implicit segments after COMMIT. Timeout checks
cover known/unknown/disabled/excessive values, savepoint restoration and NOWAIT
without bypassing later index checks. The authored `fixtures/table-locks.sql`
workflow runs in the CLI suite under separate and simple dispatch.

The PostgreSQL oracle now checks actual held modes through pg_locks, idle LOCK
SQLSTATE 25P01, implicit blocks and relation lists/markers. These added database
cases have not been executed locally or in remote CI. Script compilation is
reported separately; no live contention, deadlock or privilege test is claimed.
Final local follow-up validation passed 75 unit/documentation tests on each of
Wasm, Wasm-GC, JavaScript and Linux native with the October 16 toolchain. The full
single-file/batch/saved-report CLI suite passed on all four targets, including
actual native process execution. Formatting, interface regeneration and strict
all-target compilation passed. All six generated SARIF examples, including the
restored artifact, passed the external official schema. This is local evidence;
no new remote CI run or Windows native execution is claimed.

Saved-report tests check typed and canonical JSON round trips, including Unicode,
CRLF, NUL and oversized SQL already represented by an incomplete report. They
reject duplicate decoded keys, unknown fields/versions, non-integral/overflowing
counts, invalid Unicode, malformed metadata and invalid UTF-16 spans. CLI checks
save real upstream fixture reports, render all three formats with their original
exit codes, reject malformed files/arguments and then successfully load a valid
report. `_build/sarif-restored.json` is available for external schema validation.
This validates artifact structure and preservation, not the truth of findings.
On the October 16 toolchain, all 68 unit/documentation tests and the CLI suite
passed on Wasm, Wasm-GC, JavaScript and actual Linux native execution. Strict
all-target compilation and format/interface checks passed. The restored SARIF
sample passed the external official schema using the jsonschema CLI. No new
remote CI run is claimed before a push.

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
