# Pin XcodeGen and regenerate the Xcode project

Suggested labels: `build`, `tooling`, `developer-experience`  
Priority: High

## Summary

Make Xcode project generation deterministic by checking the required XcodeGen
version, using the explicit project spec, and regenerating—not manually
editing—`Rewrite.xcodeproj`.

## Value

The repository treats `project.yml` as the source of truth. Generator-version
drift or manual project edits can omit source/test files, lose resources, and
produce noisy unrelated diffs. A reproducible bootstrap prevents local and CI
build graphs from diverging.

## Existing implementation to reuse

Source branch: `cloudai/build-rewrite-app-bd38`

- `scripts/bootstrap.sh`
- Pinned XcodeGen installation in `.github/workflows/ci.yml`
- Source commits: `012faea` and `52f6e6b`

The bootstrap checks for XcodeGen `2.46.0` and runs:

```sh
swift scripts/generate-icon.swift
xcodegen generate --spec project.yml
```

## Required implementation for `main`

1. Select and document the repository's supported XcodeGen version.
2. Make `bootstrap.sh`:
   - fail clearly when XcodeGen is absent;
   - compare against the selected version robustly;
   - run from any caller working directory;
   - pass `--spec project.yml`;
   - regenerate icon assets before project generation.
3. Use the same XcodeGen version in local docs and CI.
4. Express every source, test, resource, entitlement, and build setting in
   `project.yml`.
5. Add `PrivacyInfo.xcprivacy` as an explicit resource.
6. Regenerate `Rewrite.xcodeproj` after all spec/file changes.
7. Remove orphan placeholder IDs and hand edits by replacing the committed
   project with generator output.
8. Consider a CI cleanliness check that regenerates the project and fails if
   `git diff --exit-code Rewrite.xcodeproj` is nonempty.

## Acceptance criteria

- `./scripts/bootstrap.sh` succeeds with the documented tool version.
- It emits a clear remediation message for a missing/wrong version.
- Two clean generations produce identical project output.
- All production Swift files are in the app target.
- All test Swift files are in the test target.
- Assets and the privacy manifest are in the Resources phase.
- The committed project has no unexplained manual IDs or missing file
  references.
- CI and local generation use the same spec and generator version.

## Verification

```sh
./scripts/bootstrap.sh
git diff --exit-code -- Rewrite.xcodeproj
xcodebuild \
  -project Rewrite.xcodeproj \
  -scheme Rewrite \
  -configuration Debug \
  -derivedDataPath DerivedData \
  test
```

Run bootstrap twice and confirm the second run creates no diff.

## Dependencies

- Coordinate resource configuration with
  `02-package-privacy-manifest.md`.

## Do not copy as-is

Do not copy the source branch's manually edited `project.pbxproj`. It contains
stale or incomplete references. Also do not keep the branch's current
`project.yml` behavior that excludes the privacy manifest without explicitly
adding it to the Resources phase.
