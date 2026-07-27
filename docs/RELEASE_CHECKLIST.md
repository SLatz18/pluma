# Release checklist

Use the common checks below for every distributed build, then follow the
section for the selected distribution channel.

## Automated verification

- Run `./scripts/bootstrap.sh`.
- Run the macOS 26 CI workflow and confirm all tests pass.
- Confirm the built app contains `Assets.car` and
  `Contents/Resources/PrivacyInfo.xcprivacy`.
- Confirm the app links no legacy Carbon hotkey implementation and requests no
  Input Monitoring or Accessibility permission.

## Archive and signing

1. Confirm the final product name and bundle identifier.
2. Increment `MARKETING_VERSION` when appropriate and always increment
   `CURRENT_PROJECT_VERSION` for a new upload.
3. Set the Release build’s Apple Developer team in Xcode.
4. Archive with Xcode’s Product → Archive command.
5. Inspect the signed app’s entitlements and confirm it contains only App
   Sandbox and outgoing network access.

Do not commit a personal `DEVELOPMENT_TEAM` value to `project.yml`.

### Mac App Store

1. Validate the archive in Organizer before upload.
2. Generate the archive’s Privacy Report in Organizer and reconcile it with the
   App Store Connect privacy answers.

### Direct distribution

1. Sign with a Developer ID Application certificate and enable the hardened
   runtime.
2. Submit the archive to Apple’s notary service with `notarytool`.
3. Staple the successful notarization ticket with `stapler`.
4. Verify the distributed artifact with `codesign --verify` and
   `spctl --assess`.

## Manual QA on a clean Mac

- Test Apple Intelligence when available, disabled, downloading, rate limited,
  and given text that exceeds its context window.
- Test Ollama when stopped, running with no models, running with multiple
  models, returning an error, and timing out.
- Test **Edit with Rewrite** in TextEdit, Mail, Notes, and at least one browser
  editor.
- Verify Shift-Command-E conflicts fall back to the Services menu and that a
  user-assigned Hyperkey shortcut works.
- Verify Escape and Command-period cancel a pending Service request.
- Confirm leading/trailing whitespace and multiline selections are preserved.
- Test VoiceOver, Full Keyboard Access, light/dark appearance, and reduced
  motion.
- Confirm no selected or playground text is persisted after relaunch.

## Submission

- Publish the repository privacy policy URL in App Store Connect and keep the
  in-app link working.
- Review Apple’s current
  [Foundation Models acceptable-use requirements](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/).
- Review the current
  [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
  and macOS release notes.
- Complete accurate screenshots, support URL, category, age rating, and privacy
  nutrition-label answers.
