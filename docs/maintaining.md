# Maintainer handoff

Verification below creates local ZIP archives and performs no registry upload.
Publishing is a separate, authenticated maintainer action; CI does not publish
packages or create release tags.

## Reproduce a candidate

Use stable `0.10.16+b1a0e846e` for compiler and core, as pinned in CI. Run from
the repository root. Git and MoonBit must be on PATH; JavaScript needs Node.js.
Native needs a C compiler. The package consumer uses Windows tar or Linux/macOS
unzip. Dependencies are resolved normally by `moon update`.

```text
moon version --all
moon update
moon fmt --check
moon info
git diff --exit-code -- pkg.generated.mbti cmd docs/pkg.generated.mbti
moon check --target all --deny-warn
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon test --target native --deny-warn
moon fmt --check scripts/e2e.mbtx scripts/postgres_probe.mbtx scripts/consumer.mbtx scripts/ci_e2e.mbtx scripts/differential.mbtx scripts/validate_sarif.mbtx
moon check scripts/e2e.mbtx --deny-warn
moon check scripts/postgres_probe.mbtx --deny-warn
moon check scripts/consumer.mbtx --deny-warn
moon check scripts/ci_e2e.mbtx --deny-warn
moon check scripts/differential.mbtx --deny-warn
moon run scripts/differential.mbtx --self-test
```

Run native commands on Linux/macOS. Windows portable coverage does not establish
Windows native runtime support. See [validation](validation.md) for observed
platform evidence and the disposable PostgreSQL oracle.

```text
moon run scripts/e2e.mbtx wasm
moon run scripts/e2e.mbtx wasm-gc
moon run scripts/e2e.mbtx js
moon run scripts/e2e.mbtx native
moon run scripts/consumer.mbtx wasm
moon run scripts/consumer.mbtx wasm-gc
moon run scripts/consumer.mbtx js
moon run scripts/consumer.mbtx native
moon run scripts/ci_e2e.mbtx wasm
moon run scripts/ci_e2e.mbtx wasm-gc
moon run scripts/ci_e2e.mbtx js
moon run scripts/ci_e2e.mbtx native
```

For external SARIF checks, use Python 3.12 with
`python -m pip install -r validation/requirements.txt`, then run
`moon run scripts/validate_sarif.mbtx` and
`moon run scripts/validate_sarif.mbtx --self-test` after generating e2e artifacts.
See [schema pins, profile and offline cache usage](sarif-validation.md).

Run these sequentially from a single checkout: CLI suites write shared _build
artifacts. Each consumer run instead creates its own fresh temporary workspace.
The scripts print a target-specific success line and return 0 on success. The
e2e suite intentionally checks CLI exits 1 and 2 as expected outcomes.

## Keep the delivery contract intact

- Edit `README.mbt.md` and keep `README.md` identical. The packaged-consumer check
  enforces the mirror. The short README and `docs/reference.mbt.md` both contain
  executable examples; `docs/moon.pkg` keeps detailed examples in the test suite.
- Regenerate interfaces with `moon info`; inspect changes rather than editing
  `.mbti` files. The docs package exports no API. The root generated interface is
  the public library contract.
- Extend a closed SQL grammar only when every new clause has represented
  semantics, diagnostics and rejection tests. Unsupported input must remain
  incomplete and retain source; unknown statements must not silently reset
  transaction/timeout state.
- Preserve archive version-1 behavior and deterministic ordering. New report
  fields or decoder changes need compatibility and round-trip coverage. Baseline
  acceptance must not erase findings or turn incomplete input into a pass.
- Update THIRD_PARTY.md for reused code, fixtures or external semantic resources.
  Retain `fixtures/RIVER_LICENSE` and the copied MIT notices in source archives.
- `.moonignore` is an allowlist. When adding a package/resource needed by the
  distribution, include it explicitly and extend `scripts/consumer.mbtx`'s
  required-entry checks. A successful checkout build alone is insufficient.

`moon package` makes a local ZIP without publishing. The consumer check extracts
that ZIP and compiles an independent dependency; it excludes the original
library checkout from the workspace. The consumer template remains in Git,
outside the library ZIP. Failed consumer workspaces are retained for diagnosis.

## Publish a reviewed version

Finish the checks above and inspect the package contents before uploading.
Check `moon whoami`: this module is published under the Mooncakes account
`cn-xjr`, which is separate from Git author identity and browser sign-in state.
The module version and `ReviewArchive` tool version must agree. Never overwrite
an existing release; use a new semantic version for subsequent changes.

```text
moon view cn-xjr/migration_lens --versions --json
moon whoami
moon publish --dry-run
moon publish
moon view cn-xjr/migration_lens@0.1.0 --json
```

The initial release can return 404 for the first command. With the pinned CLI,
a dry run can report a nonzero exit despite the service returning HTTP 202 and
`Dry run completed successfully. No changes were made.` Inspect that response;
do not interpret it as an upload or suppress errors from an actual publication.

After publishing, copy `examples/consumer` into a fresh directory outside all
MoonBit workspaces. Run `moon add cn-xjr/migration_lens@0.1.0`, then `moon check`,
`moon test` and `moon run .` for Wasm, Wasm-GC and JavaScript. Also execute native
on a system with a working C compiler. Do not create a local library workspace
override: this check must download the release from Mooncakes. Record the exact
version, registry result and observed runtime results in validation.md.

## Record a verifiable result

Update current evidence in validation.md and implemented changes in CHANGELOG.md.
Keep the historical notes separate. Do not turn planned features or an unrun CI
definition into success claims; use the exact pushed commit's Actions result.

Before committing, inspect the working tree, use the configured owner identity,
stage explicit files and review the staged diff. After an authorized push,
compare local HEAD with remote main and inspect every CI job. A prior green run
does not establish that a later revision passes. Preserve history when fixing a
failed run; historical red entries remain valid records of earlier revisions.

The next capability should have independent downstream value. Caller-supplied
catalog facts or another closed DDL workflow remain possible future work;
full PostgreSQL parsing, execution and measured lock prediction are not delivered.
