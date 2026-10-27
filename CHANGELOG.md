# Changelog

## 0.1.0 — 2026-10-28

Initial package release. The capabilities below are implemented; registry
installation evidence is recorded separately in [validation](docs/validation.md).

- Added version-2 review archives with explicit project/tool/rule/database
  provenance, preserved execution/timeout facts and checked baseline comparison.
  Existing v1 contracts remain available; legacy reports are not relabeled.
- Added a complete manifest-to-artifacts CI command with checked baseline gates,
  failure status, fresh output protection and an external-application workflow.
- Added seeded transaction/savepoint/timeout differential testing against
  PostgreSQL 18, deterministic generation and persisted/replayable counterexamples.
- Fixed the differential verdict accepting an earlier 25001 warning when a
  later server error had a different SQLSTATE; crashes and ambiguous output fail.
- Added checksum-pinned official SARIF schema validation, pinned validation-only
  dependencies, conservative GitHub profile checks and negative/recovery CI tests.

- Offline PostgreSQL 18 migration review with explicit separate/simple-query
  dispatch, caller transaction state, chaining and savepoint handling.
- Session/local lock_timeout tracking across commit, rollback, RELEASE and
  ROLLBACK TO, with opt-in finite/maximum waiting policies and caller entry facts.
- Index creation, removal, single-index rebuild/rename/storage movement,
  explicit table locks and scoped maintenance workflows.
- Staged foreign-key installation/validation, existing unique-index constraint
  attachment and column SET NOT NULL review, retaining catalog/data caveats.
- Deterministic text, strict version-1 JSON report/batch archives, SARIF 2.1.0,
  and complete-report baseline gates that preserve accepted findings.
- Fail-closed unsupported input, bounded scanning and source preservation;
  strict UTF-8 file adapters with actionable errors.
- Fixed CR-terminated line comments hiding subsequent SQL; regression coverage
  includes LF/CRLF/CR, all PostgreSQL whitespace and actual file input.
- Local archive allowlist and a separate downstream module that checks, tests
  and runs against the extracted library on all four supported targets.
- Tested quickstart and detailed reference, current validation evidence, and CI
  execution across three operating systems plus PostgreSQL 18 semantic probes.

The original public review/report API and archive format remain unchanged by
the correctness, packaging and documentation preparation on 2026-10-26–27.
See [scope and limitations](docs/reference.mbt.md) before integrating.
