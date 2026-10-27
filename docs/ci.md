# Complete CI review workflow

`cmd/ci` joins manifest loading, v2 provenance, full report export and an optional
checked baseline gate. It never executes SQL or accepts a baseline automatically.

From the MigrationLens checkout root:

```text
moon run cmd/ci -- orders-service fixtures/ci-review-manifest.json _build/review-first
moon run cmd/ci -- orders-service fixtures/ci-review-manifest.json _build/review-accepted _build/review-first/archive.json
```

Use fresh output directories each time; their parents must already exist.
The first command exits 1 for the index rename's locking warning. After explicitly
reviewing and accepting that report as a baseline, the second exits 0 because
there are no new findings. Its absolute report still records the original warning.
`moon run scripts/ci_e2e.mbtx wasm` verifies these outcomes and failure recovery
with fresh temporary directories. Other targets: wasm-gc, js and native.

## Inputs, artifacts and failure behavior

Arguments: `<project> <manifest.json> <fresh-output-directory> [trusted-v2-baseline]`.
Project identity must remain stable across runs. The strict manifest is the same
version-1 format used by cmd/batch; entries use repository-relative SQL paths and
explicit execution/timeout facts. Paths resolve from the process working directory,
not the manifest's parent. Input files must be valid UTF-8.

| Artifact | Meaning |
| --- | --- |
| `status.json` | Version 1 integration status: gate exit, absolute exit or null, baseline-used flag and diagnostic message |
| `archive.json` | Version 2 complete review evidence, including incomplete reports and every source/context |
| `report.txt` | Full human-readable review with provenance |
| `report.sarif.json` | All findings, source and completeness for code-scanning consumers |
| `delta.json`, `delta.txt` | Checked baseline difference, produced only after successful comparison |

A fresh output directory receives a failing initial status before inputs are
read. Absolute reports are saved before comparison, so findings, an incompatible
baseline or a missing baseline do not hide current review evidence. Input/read
failures can leave only status.json. Export/write failures leave the artifacts
already written; inspect status and process exit together. `absolute_exit_code`
is null if the overall operation failed before its final status was recorded.

Exit 0 means a clean absolute review or no introduced baseline findings. Exit 1
means covered findings/new findings. Exit 2 means incomplete input, invalid
configuration, incompatible baseline or I/O failure. An accepted baseline does
not make an incomplete review pass. V1 reports remain viewable with existing
report CLIs, but must be regenerated for provenance-checked CI comparison.

Existing output files/directories are refused without modification. This keeps
old successful outputs from being uploaded after a new failed run. Give each run
its own caller-owned directory; concurrent writers to the same destination are
not supported. If directory creation/status writing itself fails, the process
prints the error and exits 2; a writable report directory cannot be guaranteed.

## Run against another application's files

Build the JavaScript CLI in a separate tool checkout, then execute it with Node
from your application's root. This preserves application-relative path labels:

```text
moon -C .tools/migrationlens update
moon -C .tools/migrationlens run --target js --build-only cmd/ci
node .tools/migrationlens/_build/js/debug/build/cmd/ci/ci.js my-service ci/migrations.json review-artifacts ci/accepted-baseline.json
```

The `.tools/migrationlens` directory is a source checkout of this repository,
not a registry install. Pin it to a reviewed commit in real integrations.
Node.js must be on PATH. The external-application working-directory behavior is
executed by the JavaScript end-to-end test, using its own SQL and manifest.

Copy/adapt [ci-review.yml](ci-review.yml) for GitHub Actions.
It builds the tool separately, runs the gate from the application root and uses
`if: always()` to upload artifacts after a failing review. It does not mask the
gate's nonzero exit, publish a package or require code-scanning write permission.
It also validates an available SARIF file using the pinned schema/tool profile,
even when the review found issues. See [SARIF validation](sarif-validation.md).
The example's paths/project ID are placeholders to adapt, not hard-coded CLI rules.
Repository-level integration tests execute the workflow logic on supported
targets; this example has not been installed into an external user's repository.

GitHub's artifact handling follows its official
[store/share guide](https://docs.github.com/en/actions/tutorials/store-and-share-data)
and [status-expression reference](https://docs.github.com/en/actions/reference/workflows-and-actions/expressions#always).
SARIF export alone does not upload code-scanning results. Keep any optional upload
permission and repository policy decision in the downstream workflow.
