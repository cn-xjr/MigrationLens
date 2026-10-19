// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "cn-xjr/migration_lens"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/cn-xjr/MigrationLens"

license = "Apache-2.0"

keywords = [ "postgresql", "migration", "lint", "sql" ]

preferred_target = "wasm"

description = "Offline PostgreSQL index migration review with explicit execution context"

import {
  "moonbit-community/sqlparser@0.5.1",
  "moonbitlang/x@0.5.1",
  "moonbit-community/prettyprinter@0.4.11",
}
