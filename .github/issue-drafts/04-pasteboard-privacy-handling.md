# Make clipboard rewrites comply with macOS pasteboard privacy

Suggested labels: `enhancement`, `privacy`, `macos`

## Summary

Centralize access to `NSPasteboard.general` and handle modern macOS pasteboard
privacy states explicitly.

The universal clipboard rewrite reads copied content programmatically after a
hotkey. macOS can ask the user before allowing that read and lets the user
persistently deny or allow access under Privacy & Security → Paste from Other
Apps.

## Value relative to `main`

`main` does not need this abstraction for its primary Accessibility rewrite,
because that path reads the selected UI element directly.

This issue is mandatory if the clipboard fallback is added. Without it, a
denied read looks like an empty clipboard or unexplained failure, and the user
has no recovery path.

## Reference implementation

Available on branch `cloudai/finish-rewrite-e2e-5d52`:

- `Rewrite/Services/PasteboardAccess.swift`
- Integration in `ClipboardRewriteController`
- Settings link in `Rewrite/Views/SettingsView.swift`

## Implementation

Create one helper for all clipboard-fallback reads and writes:

```swift
import AppKit
import Foundation

enum PasteboardAccess {
    enum ReadError: LocalizedError, Equatable {
        case empty
        case accessDenied
        case noStringContent

        var errorDescription: String? {
            switch self {
            case .empty:
                "Copy some text first, then press the hotkey."
            case .accessDenied:
                """
                Pasteboard access is denied. Allow Rewrite under \
                Privacy & Security → Paste from Other Apps.
                """
            case .noStringContent:
                "The clipboard does not contain plain text."
            }
        }
    }

    static func preflightHasString(
        on pasteboard: NSPasteboard = .general
    ) -> Bool {
        if pasteboard.types?.contains(.string) == true {
            return true
        }
        return pasteboard.availableType(from: [.string]) != nil
    }

    static func readString(
        from pasteboard: NSPasteboard = .general
    ) async throws -> String {
        switch pasteboard.accessBehavior {
        case .alwaysDeny:
            throw ReadError.accessDenied
        case .alwaysAllow, .ask, .default:
            break
        @unknown default:
            break
        }

        guard preflightHasString(on: pasteboard) else {
            throw ReadError.empty
        }

        guard let text = pasteboard.string(forType: .string) else {
            throw ReadError.noStringContent
        }
        guard !text.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw ReadError.empty
        }
        return text
    }

    static func writeString(
        _ text: String,
        to pasteboard: NSPasteboard = .general
    ) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func openPrivacySettings() {
        let path = """
        x-apple.systempreferences:\
        com.apple.settings.PrivacySecurity.extension?Privacy_Pasteboard
        """
        guard let url = URL(string: path) else { return }
        NSWorkspace.shared.open(url)
    }
}
```

The type preflight examines declared pasteboard types without reading the
payload. It does not eliminate the consent prompt for the subsequent string
read; it avoids reading when no plain text is present.

## Controller integration

Handle access denial separately so the user receives a useful recovery path:

```swift
do {
    let source = try await PasteboardAccess.readString()
    // Rewrite source...
} catch let error as PasteboardAccess.ReadError {
    if error == .accessDenied {
        HUDWindowController.shared.showHint(
            error.localizedDescription + " Open Settings to change this."
        )
    } else {
        HUDWindowController.shared.showHint(error.localizedDescription)
    }
}
```

Do not automatically open System Settings merely because a hotkey was pressed.
Prefer a button in Rewrite Settings or the HUD so the transition is clearly
user initiated.

## Settings integration

Add explanatory copy and a button:

```swift
Section("Privacy") {
    Text(
        "The universal flow reads your clipboard after you copy. " +
        "macOS may ask once under Privacy & Security → " +
        "Paste from Other Apps."
    )
    .font(.caption)
    .foregroundStyle(.secondary)

    Button("Open Pasteboard Settings…") {
        PasteboardAccess.openPrivacySettings()
    }
}
```

## Acceptance criteria

- Clipboard content is not read if no plain-text type is present.
- `.alwaysDeny` produces a specific, actionable error.
- `.ask` and `.default` allow macOS to present its normal consent UI.
- Allowed text is returned unchanged, including internal line breaks.
- Whitespace-only and non-text clipboard content produce clear hints.
- Output and Undo writes go through the same helper.
- Settings opens the Paste from Other Apps pane where supported.
- Failure to construct/open the Settings URL does not crash the app.
- The app does not poll or inspect clipboard contents in the background.

## Tests

- Unit-test `ReadError` messages and empty/non-text behavior with a named
  pasteboard where possible.
- Manually test first access, Ask, Always Allow, Always Deny, and revocation.
- Test copied secrets are never logged or persisted.
- Test denied access leaves existing clipboard contents untouched.

## Deployment note

The API availability should match the repository's deployment target. If the
deployment target is lowered below the introduction of
`NSPasteboard.accessBehavior`, add an availability guard and preserve a
best-effort legacy read on older systems.
