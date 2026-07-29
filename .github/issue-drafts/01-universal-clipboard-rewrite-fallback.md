# Add a universal copy → rewrite → paste fallback

Suggested labels: `enhancement`, `macos`, `accessibility`

## Summary

Add an explicit clipboard-based rewrite path for editors where the existing
Accessibility rewrite cannot read or replace the selected text.

The user flow is:

1. Select text and press Command-C.
2. Press Control-Option-Shift-Command-E.
3. Rewrite reads the copied text, runs the configured recipe, and replaces the
   clipboard contents.
4. The user presses Command-V to paste the result.

## Value relative to `main`

`main` already rewrites selections directly through Accessibility and keeps the
macOS Service as a fallback. That is the better primary experience because it
does not require manual copy/paste.

This feature adds value only when an editor does not expose enough text through
Accessibility or direct replacement fails. Canvas-based and custom editors are
the main target. It should therefore be presented as a fallback, not as a
replacement for the existing Caps Lock E flow.

## Reference implementation

A working implementation currently exists on branch
`cloudai/finish-rewrite-e2e-5d52`:

- `Rewrite/Services/ClipboardRewriteController.swift`
- `Rewrite/Services/GlobalHotkey.swift`
- `Rewrite/App/AppDelegate.swift`

Port those files rather than cherry-picking the branch wholesale, because the
branch also contains the HUD, permission handling, tests, and CI work tracked
in separate issues.

## Core implementation

Create a main-actor controller that guards against concurrent rewrites,
reprocessing its own previous output, empty input, and no-op model responses:

```swift
@MainActor
final class ClipboardRewriteController {
    static let shared = ClipboardRewriteController()

    private var isRewriting = false
    private var lastOriginal: String?
    private var lastResult: String?

    func handleHotkey() {
        guard !isRewriting else { return }
        isRewriting = true

        Task {
            defer { isRewriting = false }

            do {
                let source = try await PasteboardAccess.readString()
                guard source != lastResult else {
                    HUDWindowController.shared.showHint(
                        "Already rewrote this. Copy new text first."
                    )
                    return
                }

                let output = try await RewriteRunner.rewrite(
                    provider: Preferences.provider(),
                    intent: Preferences.intent(),
                    text: source,
                    ollamaModel: Preferences.ollamaModel()
                )

                guard output != source else {
                    HUDWindowController.shared.showHint(
                        "Looks good already — no changes needed."
                    )
                    return
                }

                lastOriginal = source
                lastResult = output
                PasteboardAccess.writeString(output)
                HUDWindowController.shared.showResult(
                    original: source,
                    revised: output,
                    intent: Preferences.intent()
                )
            } catch {
                HUDWindowController.shared.showHint(error.localizedDescription)
            }
        }
    }

    func undo() {
        guard let lastOriginal else { return }
        PasteboardAccess.writeString(lastOriginal)
        lastResult = lastOriginal
        self.lastOriginal = nil
    }
}
```

Register the fallback during app startup without disturbing `main`'s existing
rewrite and dictation shortcut manager:

```swift
ClipboardHotkeyManager.shared.start {
    ClipboardRewriteController.shared.handleHotkey()
}
```

Use a distinct Carbon signature and ID from the existing `RWRT` shortcut
manager. The reference branch uses `RWCB` and ID `100`.

## Integration requirements

- Keep the existing Accessibility selection rewrite as the primary flow.
- Use the existing `RewriteRunner`, preferences, provider, and recipe models.
- Use the privacy-aware pasteboard helper from the separate pasteboard issue.
- Show status through the HUD issue rather than activating the main app.
- Stop all registered listeners from `applicationWillTerminate`.
- Do not synthesize Command-C or Command-V; the user performs both actions.

## Acceptance criteria

- The fallback rewrites copied plain text and puts the result on the clipboard.
- Pressing the shortcut twice without copying new text does not rewrite the
  previous result again.
- A second invocation while a rewrite is running is ignored.
- Empty, non-text, unchanged, failed, and timed-out requests show clear hints.
- Undo restores the original text to the clipboard.
- Existing Caps Lock E rewrite and Caps Lock Space dictation remain unchanged.
- The shortcut does not collide with existing Carbon IDs or callbacks.
- No Accessibility event injection is used for copy or paste.

## Tests

- Controller does not start two simultaneous rewrites.
- Previous generated output is detected as stale clipboard input.
- No-op output does not overwrite clipboard history.
- Undo restores the original text.
- Manual verification in a native editor, Electron editor, and custom/canvas
  editor.

## Dependencies

- Pasteboard privacy handling issue.
- Change-summary HUD issue.
- Standard Carbon hotkey registration; enhanced Input Monitoring is optional
  and tracked separately.
