# Document the local test command

Suggested labels: `documentation`, `developer-experience`
Priority: Low

## Summary

Add the canonical `xcodebuild` test command to the README next to the existing
build instructions.

## Value

Contributors should not need to infer the scheme, destination, configuration,
or DerivedData path. A copyable command reduces skipped tests and keeps local
verification aligned with CI and `CLAUDE.md`.

## Existing implementation to reuse

Source branch: `cloudai/build-rewrite-app-bd38`

- `README.md`
- Source commit: `012faea`

The branch adds:

```sh
xcodebuild \
  -project Rewrite.xcodeproj \
  -scheme Rewrite \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData \
  test
```

## Required implementation for `main`

1. Keep the command beside build/bootstrap instructions.
2. State that `./scripts/bootstrap.sh` must be run after adding/removing files
   or changing `project.yml`.
3. Keep the command identical to the local form used by maintainers and
   semantically aligned with CI.
4. Mention the required Xcode/XcodeGen versions in one authoritative location
   rather than duplicating conflicting versions.
5. Reconcile `CLAUDE.md`, which currently describes testing as appending
   `test` to its build command, with the standalone canonical command chosen
   for the README.

## Acceptance criteria

- A contributor can copy the documented commands from a clean checkout and run
  the full test suite.
- README, `CLAUDE.md`, bootstrap, and CI refer to the same project, scheme, and
  generator workflow.
- The command does not require a personal development-team value.

## Verification

Follow the README from a clean checkout:

1. Install/select the documented tools.
2. Run bootstrap.
3. Run the documented test command.
4. Confirm all tests execute.

## Dependencies

- `13-pin-xcodegen-and-regenerate-project.md`
- `01-add-ci-build-test-release-verification.md`

## Do not copy as-is

The command itself is suitable, but update surrounding version/tooling text to
match whatever XcodeGen and Xcode versions `main` adopts.
