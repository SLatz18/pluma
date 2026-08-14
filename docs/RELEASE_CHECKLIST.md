# Release checklist

Use the common checks below for every distributed build, then follow the
section for the selected distribution channel.

> Origin note: this checklist was first drafted during the app's earlier
> Services-only, sandboxed architecture and has been updated for the current
> design (Carbon hotkeys + Accessibility insertion, no App Sandbox). See
> `docs/SHIPPING_DECISIONS.md` for the decision history.

## Automated verification

- Run `./scripts/bootstrap.sh`.
- Run the macOS CI workflow (`.github/workflows/ci-full.yml`) and confirm all
  tests pass.
- Confirm the built app contains `Assets.car` and
  `Contents/Resources/PrivacyInfo.xcprivacy`.
- Run `python3 scripts/validate-shipping.py` — it enforces the privacy
  contract: no analytics SDKs, Ollama pinned to loopback, entitlements limited
  to outgoing network access, and no App Sandbox (sandboxing is incompatible
  with Accessibility-based cross-app insertion).
- Run `./scripts/check-design-system.sh` against `main`.

## Archive and signing

1. Confirm the final product name and bundle identifier.
2. Increment `MARKETING_VERSION` when appropriate and always increment
   `CURRENT_PROJECT_VERSION` for a new upload.
3. Local development builds sign with the stable **Local Self-Signed**
   identity so Accessibility/TCC grants survive rebuilds. Distribution builds
   need a Developer ID Application certificate instead.
4. Inspect the signed app's entitlements and confirm they contain only
   outgoing network access (`com.apple.security.network.client`).
5. When moving to a real signing identity, migrate `KeychainStore` to the
   data protection keychain (see the note in `CLAUDE.md`).

Do not commit a personal `DEVELOPMENT_TEAM` value to `project.yml`.

## Direct distribution

1. Export the app signed with a Developer ID Application certificate and the
   hardened runtime enabled.
2. Package the signed app as the final ZIP, DMG, or PKG.
3. Submit that packaged distribution artifact to Apple's notary service with
   `notarytool`.
4. After acceptance, staple the ticket to the app before rebuilding a ZIP, or
   staple the DMG/PKG directly. ZIP files themselves cannot be stapled.
5. Verify the final artifact with `codesign --verify` and `spctl --assess`.

Note: the Mac App Store requires the App Sandbox, which pluma deliberately
does not use. MAS distribution would require re-architecting cross-app
insertion; it is out of scope.

## Manual QA on a clean Mac

- Grant Accessibility on first launch and verify selection rewrite, ghost-text
  autocomplete, and insertion work in TextEdit, Mail, Notes, and at least one
  browser editor.
- Test each Caps chord: selection rewrite (⇪E), push-to-talk dictation
  (⇪Space), and Reader (⇪L) — with and without a Hyperkey/Superkey app running
  (the in-app Caps expander should auto-pause).
- Test the **Edit with pluma** Service as the fallback path.
- Test Apple Intelligence when available, disabled, downloading, rate limited,
  and given text that exceeds its context window.
- Test Ollama when stopped, running with no models, running with multiple
  models, returning an error, and timing out.
- If an OpenAI key is configured, verify key validation, rewrite, dictation,
  and Reader TTS paths — and that removing the key cleanly falls back.
- Confirm leading/trailing whitespace and multiline selections are preserved.
- Test VoiceOver, Full Keyboard Access, light/dark appearance, and reduced
  motion.
- Confirm no selected text, transcript, or audio is persisted after relaunch;
  style memory and style profile remain the only content stores, both opt-in
  (see `PRIVACY.md`).

## Submission / publication

- Keep the repository privacy policy (`PRIVACY.md`) accurate and linked from
  the app.
- Review Apple's current
  [Foundation Models acceptable-use requirements](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/)
  and macOS release notes.
