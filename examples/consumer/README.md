# Independent MigrationLens consumer

This is a separate MoonBit module using only MigrationLens's public API.
Its manifest depends on `cn-xjr/migration_lens@0.1.0`. Copy this directory outside
the library workspace and run `moon update`, `moon test` and `moon run .` to
exercise the registry dependency. No publisher account is needed to install it.

From the repository root, run `moon run scripts/consumer.mbtx wasm`. The script
packages and extracts the local library, creates an isolated workspace, runs the
four consumer tests and this module's executable. Other target arguments are
`wasm-gc`, `js` and `native`; native requires a C compiler.

See [the complete workflow](../../docs/consumer.md). No registry upload occurs.
