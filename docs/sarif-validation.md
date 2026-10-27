# Reproducible SARIF validation

After running the normal CLI and CI workflow suites, use Python 3.12 and the
pinned validation-only tools:

```text
python -m pip install -r validation/requirements.txt
moon run scripts/validate_sarif.mbtx
moon run scripts/validate_sarif.mbtx --self-test
```

Default validation covers ten real outputs: clean/finding/incomplete single
reports, batch/session reports, restored single/batch archives, and clean/finding/
incomplete v2 CI artifacts. Existing e2e round trips/determinism tests still check
report preservation; validation does not rewrite, fill defaults or drop findings.
CI runs this workflow on Linux, macOS and Windows after artifact generation.

`MIGRATIONLENS_PYTHON` selects an interpreter, such as a dedicated virtual
environment. Otherwise `python` must resolve to the environment containing the
pinned tools. Automation is implemented in MoonBit scripts; no Python script is
authored or added to the library. Sources/licenses are recorded in
[validation/tooling-sources.md](../validation/tooling-sources.md).

## Schema identity and offline use

[sarif-schema-lock.json](../validation/sarif-schema-lock.json) pins OASIS SARIF
2.1.0 Errata 01, repository revision
`a560296ca8c921f3bdb8d4a8db57ab83dae968a7` and SHA-256
`c3b4bb2d6093897483348925aaa73af03b3e3f4bd4ca38cef26dcb4212a2682e`.
The commit URL and official edition URL have been checked to contain identical
bytes. The script downloads from the fixed revision, using the edition URL only
as a network fallback, then checks the checksum before invoking the validator.

The downloaded schema is cached under `_build/validation/`; it is not committed
or distributed in the source ZIP. Cached bytes are checked on every invocation.
A mismatch fails validation. It is not silently replaced or accepted.
`MIGRATIONLENS_SARIF_SCHEMA` selects an existing offline copy, still subject to
the same checksum. With that copy and installed dependencies, validation needs
no schema download or private infrastructure. Source updates require an explicit
lock/hash review; no moving remote schema is trusted at validation time.

`check-jsonschema 0.39.0`, jsonschema and their transitive packages are pinned
in requirements.txt. Python's pip hash and gzip CLIs supply checksum/compressed
size checks. The pinned rfc3986-validator enables the validator's URI format
checks rather than relying on an optional format provider being preinstalled.
Every command receives an argument array, without shell evaluation.

## GitHub profile and its boundary

The default static profile targets MigrationLens's one-file-per-run output:
SARIF 2.1.0, 1..20 runs, nonempty tool/rule/message data, consistent rule indexes,
one canonical repository-relative artifact/location per result, and positive
source lines. It rejects duplicate rule IDs and broken references.

The profile allows at most 25,000 rules and conservatively caps results at 5,000
per run to avoid GitHub's documented display truncation. It also caps actual gzip
output at 10,000,000 bytes, using the Python CLI's default compression. Downstream
recompression may differ. Exceeding a limit fails with a diagnostic; nothing is
truncated or removed. These conservative guards are not a full server-side
ingestion emulator. Repository permissions, symlinks, PR-diff visibility and
upload/fingerprint policy still belong to the downstream integration.

For other SARIF consumers, validate only against the official schema:

```text
moon run scripts/validate_sarif.mbtx --schema-only path/to/report.sarif.json
```

The generic library exporter remains unchanged and preserves larger/multi-file
reports. The default profile is a separate validation gate. No SARIF upload is
performed by this script. GitHub requirements are checked against the official
[SARIF support reference](https://docs.github.com/en/code-security/reference/code-scanning/sarif-files/sarif-support).

The self-test exercises malformed documents, invalid levels/lines/fields,
rule-reference and URI failures, 20/21-run and 5000/5001-result boundaries, schema
checksum refusal through the actual command, recovery and unchanged input files.
Its recursive cleanup is restricted to the exact fresh task-owned temp directory.

For a separate tool checkout, the application-root workflow can invoke
`moon -C .tools/migrationlens run scripts/validate_sarif.mbtx ../../review-artifacts/report.sarif.json`.
The checked URI labels still refer to application files; static validation does
not require those source files to be present in the tool checkout.
