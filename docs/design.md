# MigrationLens design

MigrationLens reviews existing PostgreSQL 18 migration SQL. Its independent
value is combining statement semantics with caller-supplied execution context.
It does not generate migrations, compare schemas, execute DDL, or certify safety.

## Three workflows

1. A backend maintainer checks an index migration before CI merges it. The
   runner starts a transaction before sending the file. A concurrent index
   operation must produce an error with a source range and a suggested action.
2. A tool author disables the runner's transaction wrapper but sends the whole
   file in one simple-query message. A preceding SET makes this a multi-statement
   implicit transaction. The same index must be reviewed differently from
   individually dispatched statements. Unknown dispatch cannot yield a pass.
3. A maintainer sets a local timeout, uses savepoints, then adds an index. The
   review must explain whether a finite lock timeout actually applies, including
   rollback restoring previous settings. Session defaults are unknown unless
   established by this input; absence is not evidence of a zero timeout.

## Contract and architecture

The root package owns public review, diagnostic, source-range and execution
types. A SQL scanner preserves original UTF-16 offsets and statement text;
the pinned sqlparser validates CREATE INDEX. Closed grammars validate DROP INDEX
and transaction/timeout controls without dropping unrepresented clauses.
Unsupported syntax is an
explicit incomplete finding. Review is deterministic and has no database I/O.
Reporting uses the original source; there is no lossy SQL reserialization.

The minimal API is `review_sql`, `Report::exit_code`, `Report::to_text` and
`Report::to_json`, plus fallible `Report::to_sarif` for code scanning consumers.
Execution mode is mandatory. Reports expose findings and
analysis completeness. Completeness describes only the documented rule set,
never all PostgreSQL semantics or successful execution against a real catalog.

The portable library targets Wasm, Wasm-GC, JavaScript and native. The CLI
accepts UTF-8 files through an adapter; no connection strings are accepted.
PostgreSQL catalog facts, table size and concurrent workload remain unknown.
No automatic replacement of ordinary indexes with concurrent indexes occurs.

## Capability sequence

* Runnable index review: lexical boundaries, parser coverage, blocking-index
  findings, report formats, file workflow, tests, example and portable CI.
* Execution context: explicit and implicit transactions, unknown runner state,
  concurrent-index incompatibility and transaction-control diagnostics.
* Timeout scopes: transaction-local/session settings, savepoint rollback,
  reset/unknown behavior, and PostgreSQL execution probes.
* Transaction chaining: END/ABORT aliases and new explicit transaction baselines,
  with diagnostics for chaining outside an explicit transaction.
* Index cleanup: qualified/quoted name lists and CASCADE/RESTRICT; forbidden
  concurrent combinations receive actionable errors.
* Bounded lock waiting: optional caller maximum on effective milliseconds,
  library and CLI workflows, inclusive boundaries and invalid-policy diagnostics.
* Single-index maintenance: REINDEX INDEX reuses dispatch/timeout review and
  warns about catalog-dependent partition restrictions.
* Code scanning reports: SARIF preserves source and every diagnostic, validates
  paths/spans, declares UTF-16 positions and retains incomplete-run status.
* Index replacement: concurrent create/drop followed by rename, with its own
  lock and constraint-naming warning and effective-timeout checks.
* Independent migration lists: per-file context/policy, continued coverage after
  SQL errors, severity aggregation, strict file manifests and multi-run SARIF.
* REINDEX options: explicit boolean effects and tablespace review, with ambiguous
  combinations rejected instead of silently selecting precedence.
* Connection entry facts: caller-assured initial session timeout, scope-aware
  updates, unknown external rollback baselines and audited common batch defaults.
* Saved review artifacts: strict typed restoration of version-1 single reports,
  preserving all fields, then offline text/JSON/SARIF rendering and exit codes.
* Explicit table locks: closed relation-list grammar, eight lock modes, active
  block requirements, NOWAIT-aware timeout policy and mode-specific impact.
* Trusted report baselines: exact multiset comparison with duplicate conservation,
  retained source reports, strict completeness and an explicit new-findings gate.
* Index storage placement: single-index SET TABLESPACE lock/capacity diagnostics,
  scoped timeout review and unchanged downstream dispatch semantics.
* Batch review archives: strict typed restoration, context consistency, preserved
  invalid-policy reports and offline text/JSON/multi-run SARIF rendering.
* Batch baselines: exact path/context matching with duplicate occurrences,
  preserved file/source provenance, atomic coverage checks and new-findings gates.
* Transaction start modes: closed mode-list grammar, unchanged transaction/timeout
  transitions, and explicit read-only/safe-snapshot limitations.
* Post-index statistics: bounded ANALYZE option/target grammar, maintenance-lock
  and database-wide scope findings, with SKIP_LOCKED-aware limitations.

Each capability includes its own tests, documentation and generated interface.
Later work may support caller-supplied relation facts and additional DDL, only
after preserving the existing rule contract. Full PostgreSQL parsing and
online risk prediction are not promised.

## Validation and failure behavior

Malformed lexical input stops at the ambiguous boundary and reports incomplete;
subsequent well-delimited unsupported statements can be reported independently.
Unknown statements taint downstream state instead of being treated as no-ops.
Tests must cover comments, nested comments, quoted identifiers, string and
dollar-quote delimiters, malformed input, stable ranges, deterministic JSON,
continued diagnostics and cross-target behavior. PostgreSQL probes use only
disposable tables on an explicitly selected test database.

## Evidence and differentiation

* [moon-schema-plan](https://github.com/kath61105/moon-schema-plan) receives
  Schema objects and explicitly does not parse SQL. We do not duplicate its
  planning API.
* [sqlparser 0.5.1](https://mooncakes.io/docs/moonbit-community/sqlparser@0.5.1)
  supplies AST parsing, not a migration execution-context review workflow.
* [Squawk](https://github.com/sbdchd/squawk) validates the established category;
  its rules, CI and Wasm playground mean those are not novelty claims here.
* [postgres-migrations runner](https://github.com/ThomWright/postgres-migrations/blob/dbfc5ccd7c71d77c24200d403cd72722017eca67/src/run-migration.ts)
  sends the entire migration in a single query, independently of its optional
  explicit wrapper. This is a concrete consumer execution pattern.
* [PostgreSQL protocol](https://www.postgresql.org/docs/18/protocol-flow.html#PROTOCOL-FLOW-MULTI-STATEMENT),
  [CREATE INDEX](https://www.postgresql.org/docs/18/sql-createindex.html), and
  [SET](https://www.postgresql.org/docs/18/sql-set.html) define rule semantics.

The ecosystem search does not establish uniqueness. No performance advantage
or actual downstream adoption has been measured.
