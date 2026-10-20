# Sources and licenses

The review implementation and tests are authored for this repository, except
the copied SQL fixtures below. No Squawk implementation is copied.

## Dependencies

* moonbit-community/sqlparser 0.5.1 — Apache-2.0; AST parsing.
  <https://github.com/moonbit-community/sqlparser>
* moonbit-community/prettyprinter 0.4.11 — Apache-2.0; parser dependency,
  explicitly raised to the release using current configuration files.
  <https://mooncakes.io/docs/moonbit-community/prettyprinter@0.4.11>
* moonbitlang/x 0.5.1 — Apache-2.0; CLI host adapters and parser dependencies.
  <https://github.com/moonbitlang/x>
* MoonBit core — Apache-2.0; supplied with the toolchain.
  <https://github.com/moonbitlang/core>
* moonbitlang/async 0.22.5 — Apache-2.0; standalone validation scripts only,
  not a runtime library dependency. <https://github.com/moonbitlang/async>
* CI uses actions/checkout (MIT), hustcer/setup-moonbit (MIT), GitHub-hosted
  runners and the official PostgreSQL 18 container (PostgreSQL License plus
  image dependency notices). These are validation resources, not copied code.

Distributions retain their own licenses; the root license does not replace them.

## Copied fixtures (upstream tests, not production migrations)

ThomWright/postgres-migrations revision
`dbfc5ccd7c71d77c24200d403cd72722017eca67`, MIT.

* `fixtures/postgres-migrations-concurrent.sql` copies
  `src/__tests__/fixtures/concurrent-index-2/3_index-concurrently.sql`.
* `fixtures/postgres-migrations-no-transaction.sql` copies
  `src/__unit__/run-migration/fixtures/no-transaction.sql`.

<https://github.com/ThomWright/postgres-migrations/tree/dbfc5ccd7c71d77c24200d403cd72722017eca67>

MIT License

Copyright (c) 2016 Momentum Financial Technology

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Semantic references

`fixtures/river-006-bulk-unique.sql` is an unchanged production migration from
riverqueue/river revision `f043d9813073c103d447739510745c14a4070f3c`, path
`riverdriver/riverpgxv5/migration/main/006_bulk_unique.up.sql`. It is MPL-2.0,
with the full upstream license retained in `fixtures/RIVER_LICENSE`. Source:
<https://github.com/riverqueue/river/blob/f043d9813073c103d447739510745c14a4070f3c/riverdriver/riverpgxv5/migration/main/006_bulk_unique.up.sql>.
It deliberately contains unsupported function/ALTER SQL and must return
incomplete, while preserving the original input and reporting covered indexes.

PostgreSQL 18 documentation defines the rules; no documentation text is used
as implementation or fixture. See protocol multi-statement transactions,
CREATE/DROP INDEX, SET, SAVEPOINT, ROLLBACK TO and RELEASE SAVEPOINT:
<https://www.postgresql.org/docs/18/>

Transaction chaining was also checked against PostgreSQL's REL_18_STABLE
`src/backend/access/transam/xact.c` (PostgreSQL License) to distinguish explicit
from implicit blocks. No source code or comments were copied:
<https://github.com/postgres/postgres/blob/REL_18_STABLE/src/backend/access/transam/xact.c>.
Command references: <https://www.postgresql.org/docs/18/sql-commit.html>,
<https://www.postgresql.org/docs/18/sql-rollback.html>,
<https://www.postgresql.org/docs/18/sql-end.html>,
<https://www.postgresql.org/docs/18/sql-abort.html>, and
<https://www.postgresql.org/docs/18/sql-dropindex.html>.
The added chain, drop and timeout-limit fixtures/tests are authored for this
repository under its Apache-2.0 license. Maximum lock waiting is a caller policy;
no external implementation, data or rule text was reused for that policy.

REINDEX semantics follow <https://www.postgresql.org/docs/18/sql-reindex.html>.
Its implementation, regression cases and `fixtures/reindex.sql` are authored
under the root Apache-2.0 license; no documentation examples or code were copied.

SARIF export follows the OASIS SARIF 2.1.0 specification:
<https://docs.oasis-open.org/sarif/sarif/v2.1.0/os/sarif-v2.1.0-os.html>.
An external official JSON Schema was downloaded only for local validation:
<https://github.com/oasis-tcs/sarif-spec/blob/main/sarif-2.1/schema/sarif-schema-2.1.0.json>.
These OASIS resources retain their published OASIS copyright/license notices;
neither the specification nor schema is redistributed in this repository.
No SARIF exporter implementation, examples or tests were copied. Export and
test code is authored under the root Apache-2.0 license. Validation used the
external Python jsonschema CLI (MIT), not a library/runtime dependency.

Index rename syntax/lock/constraint semantics were checked against PostgreSQL 18
ALTER INDEX: <https://www.postgresql.org/docs/18/sql-alterindex.html>.
`fixtures/replace-index.sql` and its regression cases are authored examples,
Apache-2.0; no SQL or implementation was copied from that documentation.

The batch manifest, aggregation code and tests are authored under Apache-2.0.
`fixtures/review-manifest.json` references the already-attributed PostgreSQL
migration/River fixtures and the authored replacement example without copying
or modifying them. Batch parsing uses MoonBit core's strict JSON duplicate-key
option; no additional package or external implementation is reused.

Parenthesized REINDEX option syntax and booleans follow the same PostgreSQL 18
REINDEX reference cited above. The option parser, tests and
`fixtures/reindex-options.sql` are authored under Apache-2.0; no upstream source
or documentation examples were copied. Tablespace warnings do not infer catalog
or capacity facts.

Initial session timeout handling uses the existing PostgreSQL SET/ROLLBACK
semantics and lock_timeout reference:
<https://www.postgresql.org/docs/18/runtime-config-client.html#GUC-LOCK-TIMEOUT>.
The context API, tests and `fixtures/review-session-manifest.json` are authored
under Apache-2.0. No live connection is queried and no external implementation
or fixture was copied for this capability.

The version-1 saved-report decoder, offline renderer and regression tests are
authored under Apache-2.0. They consume this project's existing JSON contract,
using MoonBit core JSON's strict duplicate-key parser; no external decoder or
report schema is copied. End-to-end inputs reuse the attributed fixtures above.

Table-lock grammar and lock conflicts follow PostgreSQL 18 LOCK and explicit
locking documentation (PostgreSQL License):
<https://www.postgresql.org/docs/18/sql-lock.html> and
<https://www.postgresql.org/docs/18/explicit-locking.html#LOCKING-TABLES>.
The implicit-block distinction was also checked against PostgreSQL REL_18_STABLE
`src/backend/tcop/utility.c` (`T_LockStmt`) and
`src/backend/access/transam/xact.c` (`CheckTransactionBlock`, `IsTransactionBlock`):
<https://github.com/postgres/postgres/tree/REL_18_STABLE/src/backend>.
These resources retain the PostgreSQL License; no source, documentation prose
or upstream SQL example is copied. The parser, diagnostics, tests, database
probes and `fixtures/table-locks.sql` are authored under Apache-2.0.

The baseline comparison contract, implementation, CLI and tests are authored
under Apache-2.0; no upstream comparison algorithm or fingerprint implementation
is copied. Keys are exact ordered JSON tuples using MoonBit core, not SARIF
fingerprints. End-to-end input extends the attributed postgres-migrations
fixture with an authored ordinary DROP INDEX statement for offline review.

Single-index SET TABLESPACE syntax, privileges and lock level were checked
against the PostgreSQL 18 ALTER INDEX reference already cited above:
<https://www.postgresql.org/docs/18/sql-alterindex.html> (PostgreSQL License).
The classifier, diagnostics, tests, pg_default lock probe and
`fixtures/move-index.sql` are authored under Apache-2.0. No documentation
example, upstream fixture or implementation was copied for this capability.

The batch archive decoder, CLI and regression cases are authored under Apache-2.0.
They implement this project's existing version-1 JSON contract with MoonBit core
JSON; no external serialization implementation or schema was copied. The e2e
archive inputs reuse the already-attributed fixtures and authored workflows.

Batch baseline matching, snapshot/provenance handling, CLI and tests are authored
under Apache-2.0. They extend this project's single-report comparison contract
using MoonBit core maps and JSON. No external matcher, baseline implementation
or test suite was copied; end-to-end archives reuse the attributed inputs above.

Transaction-mode grammar, tests and `fixtures/transaction-modes.sql` are authored
under Apache-2.0. Semantics were checked against PostgreSQL 18 BEGIN and
SET TRANSACTION documentation (PostgreSQL License):
<https://www.postgresql.org/docs/18/sql-begin.html> and
<https://www.postgresql.org/docs/18/sql-set-transaction.html>.
No upstream parser or documentation text was copied.

ANALYZE target/boolean-option handling, tests, probes and `fixtures/analyze.sql`
are authored under Apache-2.0. References are PostgreSQL 18 ANALYZE and table-level
locking documentation (PostgreSQL License):
<https://www.postgresql.org/docs/18/sql-analyze.html> and
<https://www.postgresql.org/docs/18/explicit-locking.html#LOCKING-TABLES>.
No upstream implementation or documentation text was copied.

VACUUM option/target validation, contextual diagnostics, tests, probes and
`fixtures/vacuum.sql` are authored under Apache-2.0. PostgreSQL 18 VACUUM and
table-level locking documentation (PostgreSQL License) define the behavior:
<https://www.postgresql.org/docs/18/sql-vacuum.html> and
<https://www.postgresql.org/docs/18/explicit-locking.html#LOCKING-TABLES>.
No upstream implementation or documentation text was copied. The READ ONLY
wording also follows SET TRANSACTION: DDL restrictions are not limited to
non-temporary relations.
