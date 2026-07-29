# Package and validate a privacy manifest

Suggested labels: `privacy`, `release`, `build`
Priority: High

## Summary

Add `PrivacyInfo.xcprivacy` to the Rewrite application target as a bundled
resource and validate its declarations against the APIs and data flows used by
current `main`.

## Value

A privacy manifest provides machine-readable tracking, collection, and
required-reason API declarations for distribution review. Packaging it in the
app also lets Xcode's Privacy Report and CI detect omissions.

## Existing implementation to reuse

Source branch: `cloudai/build-rewrite-app-bd38`

- `Rewrite/PrivacyInfo.xcprivacy`
- Initial manifest: commit `012faea`
- CI package verification: commits `d26b2c6` and `52f6e6b`

The existing manifest declares:

- no tracking;
- no collected data types;
- `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`.

## Required implementation for `main`

1. Review the existing declaration against current Apple documentation and an
   Organizer-generated Privacy Report.
2. Keep declarations that accurately describe `UserDefaults` usage.
3. Add any required-reason API declarations identified for current code and
   linked dependencies. Do not infer declarations merely from filenames;
   verify actual API use.
4. Add the manifest explicitly to `project.yml` as a resource. Do not only
   exclude it from the Swift source glob.
5. Regenerate `Rewrite.xcodeproj` with XcodeGen rather than hand-editing the
   project file.
6. Add CI checks that lint the source manifest and confirm the built app
   contains `Contents/Resources/PrivacyInfo.xcprivacy`.

An XcodeGen resource entry should be equivalent to:

```yaml
sources:
  - path: Rewrite
    excludes:
      - Info.plist
      - PrivacyInfo.xcprivacy
      - Rewrite.entitlements
  - path: Rewrite/PrivacyInfo.xcprivacy
    buildPhase: resources
```

Use the exact syntax supported by the pinned XcodeGen version.

## Acceptance criteria

- `PrivacyInfo.xcprivacy` is valid XML/plist data.
- The generated project includes it in the Rewrite target's Resources phase.
- A Release build contains the manifest in the app bundle.
- Tracking and collection declarations match actual product behavior.
- Required-reason declarations match the Organizer Privacy Report and current
  Apple requirements.
- CI fails if the resource is missing from the built app.

## Verification

```sh
plutil -lint Rewrite/PrivacyInfo.xcprivacy
./scripts/bootstrap.sh
xcodebuild \
  -project Rewrite.xcodeproj \
  -scheme Rewrite \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData \
  build
test -f \
  DerivedData/Build/Products/Release/Rewrite.app/Contents/Resources/PrivacyInfo.xcprivacy
```

Also generate and review Xcode's Privacy Report before distribution.

## Dependencies

- `13-pin-xcodegen-and-regenerate-project.md`

## Do not copy as-is

The source branch currently excludes `PrivacyInfo.xcprivacy` in `project.yml`
without adding an explicit resource entry. Its manually edited
`project.pbxproj` also does not reliably package the manifest.
