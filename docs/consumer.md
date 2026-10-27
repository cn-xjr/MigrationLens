# Use MigrationLens from another MoonBit module

## Install the library

From your own MoonBit module, run:

```text
moon add cn-xjr/migration_lens@0.1.0
```

Add `"cn-xjr/migration_lens" @lens` to the import block in your `moon.pkg`.
The examples in `examples/consumer/main.mbt` and `consumer_wbtest.mbt` use this
alias and only the public API. Use the pinned compiler/core release documented
in the README; JavaScript also requires Node.js, and native requires a C compiler.

The source-archive workflow below is a separate maintainer check. It uses a local
ZIP and workspace without publishing; normal dependency resolution can still
download declared dependencies. See [validation](validation.md) for the actual
registry installation evidence.

## Reproduce the packaged consumer

From a source checkout, with MoonBit and Git on PATH, run:

```text
moon run scripts/consumer.mbtx wasm
moon run scripts/consumer.mbtx wasm-gc
moon run scripts/consumer.mbtx js
moon run scripts/consumer.mbtx native
```

JavaScript needs Node.js. Native needs a working C compiler; the local native
evidence uses Linux, while CI also exercises macOS. Windows uses its bundled
`tar` for ZIP extraction; Linux/macOS need `unzip`. `MIGRATIONLENS_MOON` selects
a particular Moon executable. Scripts themselves run through the Wasm host.

The script calls `moon package`, checks the actual ZIP's licenses/source and
absence of caches or the separate consumer module, then extracts it into a
fresh temporary directory. It copies `examples/consumer` beside that extracted
library and creates a workspace using `moon work init library consumer`.
The original library checkout is not a workspace member. This catches missing
archive files and public imports that succeed only inside the original project.

The isolated consumer compiles with warnings denied, runs four tests, then
runs its executable. The tests exercise four downstream tasks:

1. A migration runner supplies dispatch/timeout facts and detects the same
   concurrent index succeeding in separate dispatch but failing in a whole-file
   simple query. Its saved report round-trips through the public decoder.
2. A rollout tool reviews NOT VALID foreign-key installation and later
   validation, retaining catalog/data warnings and exporting a SARIF report.
3. A CI tool restores saved batch reports and distinguishes accepted findings
   from a new finding, including a repeat baseline comparison with no new issues.
4. A provenance-aware CI tool restores a v2 archive and rejects changed dispatch
   before baseline comparison. See [the archive contract](archive.mbt.md).

Expected final output: `Packaged consumer checks passed on <target>` (exit 0).
The example itself prints `MigrationLens downstream consumer: index rollout reviewed`.
An error keeps its temporary workspace for inspection; a successful run removes
only the fresh directory it created. Consumer build/workspace files stay outside
the source checkout. The workspace explicitly sets LF Git attributes for Windows.

## Adapt the example for your tool

Copy `examples/consumer` into your own development workspace. Its module imports
`cn-xjr/migration_lens@0.1.0` in `moon.mod`; its `moon.pkg` imports
`cn-xjr/migration_lens` as `@lens`. Declare both the local library and your tool
as workspace members when testing a local checkout. The workspace resolves this
name locally; omit that workspace override to test the registry dependency.
See the official
[MoonBit workspace guide](https://docs.moonbitlang.com/en/latest/toolchain/moon/workspace.html).

`review_sql` and `review_migrations` are offline analyses. `complete=true`
describes coverage of the documented rule set, not successful database execution.
Baseline comparison requires complete reports and the same project/rule version.
Inspect `examples/consumer/consumer_wbtest.mbt` for public API examples; these tests
cannot access MigrationLens's private implementation through its dependency.

The ZIP is a library/CLI source distribution; the separate consumer template is
kept in the Git checkout. `.moonignore` explicitly selects code, licenses, SQL
fixtures, docs and verification scripts; developer notes and build caches are
excluded. Generating a ZIP does not publish a package or create a release tag.
