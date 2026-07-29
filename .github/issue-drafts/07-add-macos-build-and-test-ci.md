# Add macOS CI for generated-project build and tests

Suggested labels: `ci`, `quality`, `developer-experience`

## Summary

Add a GitHub Actions workflow that:

1. Checks out the repository on a macOS runner.
2. Installs XcodeGen.
3. Regenerates `Rewrite.xcodeproj` from `project.yml`.
4. Builds without code signing.
5. Runs the unit-test target.

## Value relative to `main`

This has repository-wide value, not just clipboard-fallback value.

The app depends on macOS-only frameworks and generated Xcode project metadata,
so Linux agents cannot compile it. CI catches:

- Swift and AppKit compile errors.
- Duplicate source filenames.
- Missing files in project generation.
- API availability/type errors.
- Unit-test regressions.
- Drift between `project.yml` and the committed Xcode project.

During development of the reference branch, CI immediately found signing,
duplicate-filename, delegate visibility, and Core Graphics flag errors that
could not be detected on Linux.

## Reference implementation

An initial workflow exists on branch `cloudai/finish-rewrite-e2e-5d52` at:

```text
.github/workflows/ci.yml
```

It should be adjusted to avoid duplicate runs. A workflow configured for both
`push` on feature branches and `pull_request` runs twice for every PR update.

## Proposed workflow

```yaml
name: CI

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-and-test:
    runs-on: macos-latest
    timeout-minutes: 30

    steps:
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Select Xcode
        run: |
          sudo xcode-select -s \
            /Applications/Xcode_26.5.app/Contents/Developer
          xcodebuild -version

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate project
        run: ./scripts/bootstrap.sh

      - name: Verify generated project is committed
        run: git diff --exit-code -- Rewrite.xcodeproj

      - name: Build and test
        run: |
          xcodebuild \
            -project Rewrite.xcodeproj \
            -scheme Rewrite \
            -configuration Debug \
            -derivedDataPath DerivedData \
            -destination 'platform=macOS' \
            CODE_SIGNING_ALLOWED=NO \
            test
```

## Design decisions

### Trigger only once per feature update

- Run `pull_request` for feature branches.
- Run `push` only for `main`.
- Do not also run `push` for `cloudai/**` or every feature branch.

### Disable signing

`main` may use a local signing identity for development. GitHub-hosted runners
do not have that certificate:

```text
CODE_SIGNING_ALLOWED=NO
```

must be passed to CI build/test invocations.

### Regenerate before compiling

`project.yml` is the source of truth for file membership. Regeneration catches
new files that were not manually added to `project.pbxproj`.

The optional `git diff --exit-code` step enforces that the committed project
matches generated output. If the team intentionally does not commit generated
project changes, remove this step and document that policy instead.

### Select a compatible Xcode

The repository currently targets macOS/Xcode 26. The workflow must select a
runner image containing a compatible Xcode. Avoid assuming `macos-latest`
always points to the required SDK without printing `xcodebuild -version`.

If `/Applications/Xcode_26.5.app` is unavailable on the selected image, pin a
compatible macOS runner and update the path based on GitHub's runner image
documentation.

## Acceptance criteria

- Exactly one CI run is created for each pull-request update.
- CI runs for direct pushes to `main`.
- XcodeGen completes successfully.
- Build does not require repository or developer signing certificates.
- All test targets execute.
- A compile or test failure blocks the check.
- A newer pushed commit cancels the stale in-progress run.
- Workflow logs print the selected Xcode and SDK versions.
- Project-generation drift is either enforced or explicitly documented.

## Follow-up improvements

- Cache Homebrew/XcodeGen installation if runtime becomes significant.
- Upload `.xcresult` bundles on failure.
- Add SwiftLint only if the repository adopts a shared configuration.
- Split expensive UI tests into a separate job if added later.
- Add branch protection after the workflow is stable and green.

## Security notes

- Use only read access to repository contents.
- Do not import signing certificates or provisioning profiles for unit tests.
- Pin third-party actions to reviewed major versions or commit SHAs according
  to repository policy.
