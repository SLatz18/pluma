# Publish accurate privacy and release documentation

Suggested labels: `documentation`, `privacy`, `release`  
Priority: High

## Summary

Add a repository privacy policy, shipping-decision record, and release
checklist that describe the product currently implemented on `main`.

## Value

Users need an accurate explanation of what Rewrite can read, store, and send.
Maintainers also need a repeatable signing, notarization, permissions, and
manual-QA process. Documentation reduces accidental privacy regressions and
prevents a release from being evaluated against the wrong distribution model.

## Existing implementation to reuse

Source branch: `cloudai/build-rewrite-app-bd38`

- `PRIVACY.md`
- `docs/RELEASE_CHECKLIST.md`
- `docs/SHIPPING_DECISIONS.md`
- Documentation commits: `52f6e6b` and `c5682d1`

The structure, external references, direct-distribution signing steps, and
clean-Mac QA checklist are useful starting points.

## Required implementation for `main`

Rewrite all three documents around current behavior:

### Privacy policy

Cover at least:

- Accessibility-based selected-text rewriting and autocomplete;
- Carbon global-hotkey registration;
- optional screen capture and on-device OCR context;
- microphone access, speech recognition, and dictation cleanup;
- Apple Intelligence processing;
- Ollama loopback processing and the distinction between local and cloud-backed
  Ollama models;
- any optional OpenAI transcription or cleanup path;
- local style memory and style-profile files in Application Support;
- preferences in `UserDefaults`;
- API credentials stored in Keychain;
- retention, deletion controls, logging, analytics, and telemetry.

Claims must match code. In particular, do not say all text is processed only
after a Service or playground action when autocomplete and dictation are
enabled.

### Shipping decisions

Document why the app is intentionally non-sandboxed and distributed directly:

- Accessibility and event-tap requirements;
- Carbon hotkey tradeoffs;
- screen-capture and microphone permissions;
- local and optional external provider boundaries;
- hardened-runtime and code-signing expectations.

### Release checklist

Focus on Developer ID distribution and notarization unless the architecture
changes enough to support the Mac App Store. Include:

- version/build-number updates;
- generated-project verification;
- tests and Release build;
- privacy report review;
- signed entitlement inspection;
- hardened runtime;
- notarization and stapling;
- QA for all permissions and providers;
- update/install behavior;
- privacy-policy and support URLs.

Add an in-app link to the published privacy policy or a bundled readable copy.

## Acceptance criteria

- Every user-visible data path in the current README has a corresponding
  privacy-policy explanation.
- The policy identifies which content is transient and which is persisted.
- Optional cloud processing is disclosed accurately.
- The release checklist matches a non-sandboxed Developer ID app.
- The documents do not claim Carbon, Accessibility, or screen capture are
  absent.
- The app exposes a working privacy-policy link.
- The README links to the policy and release checklist.

## Verification

- Review the documents against `README.md`, entitlements, `Info.plist`,
  provider code, autocomplete, dictation, memory stores, and Keychain code.
- Run a clean-Mac permission walkthrough and ensure every prompt is explained.
- Compare the policy and privacy manifest with Xcode's Privacy Report.

## Dependencies

- Provider and privacy behavior should be finalized before publication,
  especially:
  - `07-harden-ollama-loopback-and-local-models.md`
  - `08-harden-apple-intelligence-output-and-errors.md`
  - `02-package-privacy-manifest.md`

## Do not copy as-is

The source documents describe a Services-only, sandboxed app with no
Accessibility or Carbon hotkeys. That no longer matches `main`. They also omit
autocomplete, screen context, dictation, OpenAI, Keychain use, and local style
storage. In particular, the branch checklist requires no Carbon hotkeys or
Accessibility permission, expects App Sandbox-only entitlements, tests an
obsolete Shift-Command-E shortcut, and includes Mac App Store submission steps.
Current `main` instead requires a non-sandboxed Developer ID distribution
workflow. Reuse the organizational shape and vetted links, not those claims.
