# Current validation and limits

Evidence is maintained as of 2026-10-28. CI pins compiler/core stable
`0.10.16+b1a0e846e`: moon/moonrun `0.1.20261016`, moonc
`v0.10.16+b1a0e846e`. This is the tested reproducible release, not a claim that
every newer toolchain has been checked. Older development notes are preserved in
[validation-history.md](validation-history.md); their pending statements refer
to those earlier revisions.

## Observed evidence

| Check | Observed result |
| --- | --- |
| Formatting, generated interfaces, strict compilation | Passed; four targets checked with warnings denied |
| Library and executable documentation tests | 175 pass per target: Wasm, Wasm-GC, JavaScript, actual Linux native |
| Complete file CLI workflow | Passes all four targets, including expected finding/incomplete exits |
| Packaged dependency consumer | Four public-API tests and its executable pass per target after fresh ZIP extraction |
| Operating systems | GitHub Actions Linux/macOS/Windows portable execution; Linux/macOS native execution |
| PostgreSQL semantics | Actual PostgreSQL 18 CI probes pass; no local database execution claimed |
| SARIF output | Seven generated documents validated against the external OASIS 2.1.0 schema |
| Windows native runtime | Not verified; local MSVC/Windows SDK unavailable |
| Registry publication | Not performed; local ZIP generation only |

Public evidence before this documentation update:

- [`7f6c91c`, run 40349695555](https://github.com/cn-xjr/MigrationLens/actions/runs/40349695555):
  CR-comment correctness regression and expanded timeout tests; all four jobs pass.
- [`d34af8b`, run 40352191148](https://github.com/cn-xjr/MigrationLens/actions/runs/40352191148):
  archive/independent-consumer workflow on supported runner targets; all four
  jobs pass. Those revisions had 163 library/doc tests; the current documentation
  split preserves all 16 detailed examples and adds two quickstart tests.

Consult [Actions](https://github.com/cn-xjr/MigrationLens/actions/workflows/ci.yml)
for the exact revision being evaluated. The local native runs execute built
processes under WSL Ubuntu 22.04; a native compilation alone is not counted.
macOS evidence comes from CI. The library has no FFI; the CLI uses moonbitlang/x
filesystem/process adapters and core's strict UTF-8 decoder.

## Reproduce without a database

Follow the [README quickstart](../README.md), then the complete command list in
[maintaining.md](maintaining.md). `MIGRATIONLENS_MOON` selects the Moon executable
used by validation scripts; scripts themselves run through the Wasm host.
JavaScript requires Node.js; native requires a C compiler. Consumer extraction
requires Git plus Windows tar or Linux/macOS unzip.

```text
moon run cmd/main -- fixtures/postgres-migrations-concurrent.sql separate
moon run scripts/e2e.mbtx wasm
moon run scripts/consumer.mbtx wasm
```

All three return 0. E2e also runs real upstream fixtures and authored workflows
that intentionally return CLI exit 1 or 2, then checks them as expected outcomes.
It covers strict UTF-8 rejection, CR-only comments, source preservation, JSON
round trips, deterministic rendering, saved single/batch reports, SARIF and
baseline gates. Unit/property cases cover malformed input, Unicode ranges,
size/depth boundaries, duplicate conservation, timeout limits, recovery and
preservation of previous defaults.

The independent consumer packages the library, checks required source/licenses
and absence of caches, extracts it into a new workspace, and checks/tests/runs a
separate module using public imports. The README mirror and the detailed-doc
package are checked in that archive. It does not publish anything or require a
registry account; declared dependency downloads may still occur.

## PostgreSQL 18 execution oracle

Use a disposable PostgreSQL 18 database named `migrationlens_test`, with psql on
PATH. Set PGHOST/PGPORT/PGUSER/PGPASSWORD normally, PGDATABASE to
`migrationlens_test`, and MIGRATIONLENS_DISPOSABLE_DB to `1`.

```text
moon run scripts/postgres_probe.mbtx
```

The probe refuses other database markers/major versions. It creates and drops
only its own named test objects. A failure may leave those objects behind;
recreate the disposable database before retrying. CI supplies a fresh PostgreSQL
18 container and checks the real process results, not just script compilation.

The oracle checks SQLSTATE 25001 for concurrent-index transaction conflicts,
3B001 for missing savepoints, session/local timeout values across transaction and
savepoint transitions, and explicit versus implicit dispatch behavior. It also
checks lock modes, maintenance restrictions, staged constraint enforcement,
referential actions and nullability against real server behavior. CR-terminated
comments and vertical-tab separators have actual server probes.

Each stage is named before invoking psql; a failure includes that stage, status
and stderr. Connection environment/passwords are never printed. These are
semantic probes, not workload benchmarks, exhaustive PostgreSQL compatibility
tests or measured proof of scan avoidance.

## Evidence boundaries

The v2 archive adds automatic project/tool/rule/context compatibility checks.
V1 encoding/decoding and legacy comparison behavior are preserved. New tests
cover mismatches, strict restoration, duplicate multiplicity, independent
snapshots and invalid Unicode, including a downstream executable and four
consumer tests. Read [the archive contract](archive.mbt.md) for compatibility.

Source and resource licenses are recorded in [THIRD_PARTY.md](../THIRD_PARTY.md).
The River production fixture deliberately returns incomplete for unsupported
function/ALTER statements. It must not become a clean review merely because
some index operations are covered. Fixtures are not automatically executed.

`complete=true` covers only the documented rules/grammar. Catalog state, data,
permissions and workload are outside offline evidence. No ecosystem uniqueness,
performance advantage, broad SQL compatibility or actual downstream adoption is
claimed. Unimplemented future capabilities remain in [design.md](design.md).
