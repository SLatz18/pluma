# Add CI build, test, and release verification

Suggested labels: `ci`, `quality`, `release`  
Priority: High

## Summary

Add a least-privilege GitHub Actions workflow that regenerates the Xcode
project, validates shipping metadata, runs the macOS unit tests, builds the
Release configuration, and verifies required resources in the app bundle.

## Value

`main` currently relies on local verification. CI would catch Swift compilation
failures, stale generated-project state, test regressions, invalid plists, and
missing release resources before changes merge.

## Existing implementation to reuse

Source branch: `cloudai/build-rewrite-app-bd38`

- `.github/workflows/ci.yml`
- Initial workflow work: commit `012faea`
- Packaging checks: commit `d26b2c6`
- Pinned/checksummed tool installation and shipping checks: commit `52f6e6b`

Useful pieces include:

- `permissions: contents: read`
- A bounded job timeout
- A pinned `actions/checkout` commit
- Explicit Xcode selection
- A pinned and checksummed XcodeGen download
- `plutil -lint` checks
- Debug tests and a Release build
- Verification of `Assets.car` and `PrivacyInfo.xcprivacy`

## Required implementation for `main`

1. Start from the branch workflow, but target the Xcode and runner versions
   supported by current `main`.
2. Run `./scripts/bootstrap.sh` before building.
3. Validate `Info.plist`, the privacy manifest, and entitlements.
4. Replace the branch's current `scripts/validate-shipping.py` assumptions.
   `main` intentionally uses Carbon hotkeys, Accessibility, event taps, screen
   capture, and no App Sandbox. CI must validate that architecture rather than
   reject it.
5. Run:
   - the full Debug test suite;
   - a Release build with CI-appropriate code-signing overrides;
   - packaged-resource checks.
6. Ensure workflow shell steps fail on errors and quote paths.
7. Keep all third-party Actions pinned to immutable commit SHAs.

## Shipping validation appropriate for `main`

The replacement validator should check facts such as:

- the expected non-sandboxed entitlements;
- only approved outgoing network paths/providers;
- required microphone, speech, local-network, and any screen-capture metadata;
- the macOS Service declaration and its timeout;
- the privacy manifest being present and well formed;
- no accidental analytics or telemetry dependencies;
- the Release app containing required resources.

It must not assert that Carbon, Accessibility, `CGEventTap`, or global event
monitoring are absent because those are intentional parts of the current app.

## Acceptance criteria

- Pull requests and pushes to `main` run the workflow.
- A clean checkout can regenerate the project and compile.
- All unit tests pass in CI.
- The Release configuration builds.
- Required plists and entitlements validate.
- `Assets.car` and `PrivacyInfo.xcprivacy` exist in the built Release app.
- The workflow uses read-only repository permissions.
- The workflow contains no validator rule that contradicts documented `main`
  behavior.

## Verification

- Introduce a temporary failing test and confirm CI fails, then remove it.
- Temporarily omit the privacy manifest resource and confirm bundle validation
  fails.
- Confirm a normal run succeeds from a clean checkout.

## Dependencies

- `13-pin-xcodegen-and-regenerate-project.md`
- `02-package-privacy-manifest.md`
- `14-align-service-info-plist-metadata.md`

## Do not copy as-is

Do not copy `scripts/validate-shipping.py` from the source branch unchanged. It
requires App Sandbox and forbids APIs that current `main` deliberately uses, so
the existing workflow fails before reaching the build.
