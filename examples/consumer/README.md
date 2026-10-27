# Independent MigrationLens consumer

This is a separate MoonBit module using only MigrationLens's public API.
It depends on an unpublished local module, so use a workspace rather than
running `moon add` against the registry.

From the repository root, run `moon run scripts/consumer.mbtx wasm`. The script
packages and extracts the library, creates an isolated workspace, runs the
four consumer tests and this module's executable. Other target arguments are
`wasm-gc`, `js` and `native`; native requires a C compiler.

See [the complete workflow](../../docs/consumer.md). No registry upload occurs.
