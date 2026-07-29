# Align Service and distribution metadata in Info.plist

Suggested labels: `services`, `release`, `configuration`  
Priority: Medium

## Summary

Update `Rewrite/Info.plist` so the macOS Service declaration matches current
chain-based behavior and the declared timeout, category, and encryption status
are suitable for distribution.

## Value

Services are discovered and invoked from plist metadata rather than Swift
types. Incorrect timeout or user-data declarations can make AppKit terminate a
request unexpectedly or imply behavior the provider no longer supports.
Distribution metadata also avoids repeated manual answers during release.

## Existing implementation to reuse

Source branch: `cloudai/build-rewrite-app-bd38`

- `Rewrite/Info.plist`
- Source commits: `012faea` and `52f6e6b`

The branch adds:

- `ITSAppUsesNonExemptEncryption = false`;
- `NSServiceCategory = public.text`;
- a change from `main`'s 60,000 ms `NSTimeout` to 30,000 ms;
- removal of `main`'s obsolete `NSUserData = selectedAction`.

## Required implementation for `main`

1. Add the non-exempt-encryption declaration if accurate for all shipped
   networking and cryptography usage.
2. Categorize the Service under `public.text`.
3. Set `NSTimeout` to AppKit's intended Service budget and ensure code-level
   inner/outer deadlines finish before it.
4. Remove `NSUserData` only after confirming the current Service provider does
   not use it. `main` currently loads the ordered recipe chain from preferences,
   so stale single-action user data should not be advertised.
5. Keep UTF-8 plain-text send/return types and the current Service selector.
6. Update the singular “local writing action” Service description to explain
   the current ordered recipe-chain behavior.
7. Remove duplicate keys such as duplicate `LSUIElement` declarations.
8. Audit all current permission usage descriptions at the same time, including
   local network, microphone, speech recognition, and screen capture if a
   purpose string is required for the supported SDK/OS.

## Acceptance criteria

- `plutil -lint Rewrite/Info.plist` succeeds.
- There is exactly one `LSUIElement` key.
- The Service appears under the expected text Services category.
- Service send/return types match provider behavior.
- The declared Service timeout exceeds internal deadlines but is no longer than
  intended.
- No obsolete single-action `NSUserData` remains.
- Encryption and permission metadata accurately describe the shipping app.

## Verification

- Register/update dynamic Services and invoke **Edit with Rewrite** from at
  least TextEdit, Mail, Notes, and a browser editor.
- Test success, model failure, cancellation, and timeout.
- Inspect the built app's `Info.plist`, not only the source plist.
- Validate release metadata in Xcode Organizer.

## Dependencies

- `06-enforce-operation-timeouts.md`

## Do not copy as-is

Do not treat the plist timeout as the timeout implementation. The source branch
declares 30 seconds while its code-level timeout wiring is incomplete. The
metadata and executable behavior must be updated together.
