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
