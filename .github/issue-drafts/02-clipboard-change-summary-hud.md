# Add a non-activating change-summary HUD for clipboard rewrites

Suggested labels: `enhancement`, `ui`, `macos`

## Summary

After a clipboard rewrite succeeds, show a transient floating HUD containing:

- The rewrite recipe that ran.
- A locally computed word-level diff.
- A change count.
- A Command-V reminder.
- Undo and Done actions.

Errors and no-op results should use the same panel in a compact hint mode.

## Value relative to `main`

`main` performs direct selection rewriting and already has overlay
infrastructure for autocomplete and dictation. The clipboard fallback is less
obvious because it silently changes the clipboard rather than the document.

The HUD gives that fallback essential feedback: the user knows the rewrite
completed, sees what changed, and knows the next action is paste. The local
diff also improves trust because it is derived from the actual strings rather
than an AI-generated explanation.

This issue has medium standalone value and high value when paired with the
clipboard fallback.

## Reference implementation

Available on branch `cloudai/finish-rewrite-e2e-5d52`:

- `Rewrite/Views/HUDPanel.swift`
- `Rewrite/Views/RewriteHUDView.swift`
- `Rewrite/Services/HUDWindowController.swift`
- `Rewrite/Services/WordDiffer.swift`

## Panel implementation

Use a dedicated non-activating `NSPanel` so the source editor keeps focus:

```swift
final class HUDPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }
}
```

Host SwiftUI content with `NSHostingView`, position the panel on the display
containing the mouse pointer, and dismiss automatically:

```swift
@MainActor
final class HUDWindowController {
    static let shared = HUDWindowController()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func showResult(
        original: String,
        revised: String,
        intent: RewriteIntent
    ) {
        let view = RewriteHUDView(
            mode: .result(
                original: original,
                revised: revised,
                intent: intent
            ),
            onUndo: {
                ClipboardRewriteController.shared.undo()
                self.dismiss()
            },
            onDone: { self.dismiss() }
        )
        present(view, width: 380, autoDismissAfter: 6)
    }
}
```

## Diff implementation

Compute changes locally using an LCS over whitespace-separated tokens:

```swift
struct DiffSegment: Equatable {
    enum Kind: Equatable {
        case unchanged
        case removed
        case added
    }

    let kind: Kind
    let text: String
}

enum WordDiffer {
    static func diff(original: String, revised: String) -> [DiffSegment] {
        let old = original.split(whereSeparator: \.isWhitespace).map(String.init)
        let new = revised.split(whereSeparator: \.isWhitespace).map(String.init)

        var table = [[Int]](
            repeating: [Int](repeating: 0, count: new.count + 1),
            count: old.count + 1
        )

        for i in old.indices.reversed() {
            for j in new.indices.reversed() {
                table[i][j] = old[i] == new[j]
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }

        // Walk the table to emit unchanged, removed, and added segments.
        // See the reference branch for the complete implementation.
        return buildSegments(old: old, new: new, table: table)
    }
}
```

The issue implementation should include the complete table walk and adjacent
change-run counter from the reference branch.

## UI requirements

- Result mode shows recipe, change count, inline diff, Undo, Done, and
  Command-V guidance.
- Hint mode shows concise errors or no-op information.
- Removed words are red and struck through.
- Added words are green and emphasized.
- Panel never activates Rewrite or steals typing focus.
- Panel appears on the current display and in full-screen Spaces.
- A new message cancels the previous auto-dismiss task.
- Result timeout: approximately six seconds.
- Hint timeout: approximately three to four seconds.

## Acceptance criteria

- Successful clipboard rewrites display the actual original/revised diff.
- Undo restores the original clipboard text and dismisses the HUD.
- Done dismisses the HUD without changing clipboard contents.
- The source application remains frontmost and receives Command-V.
- Repeated HUD presentations reuse one panel without leaking windows.
- Multi-display and full-screen positioning works.
- No model-generated change summary is displayed as factual ground truth.

## Tests

- Identical text produces zero changes.
- Insertion, deletion, and replacement produce correct segment kinds.
- Adjacent removed/added words count as one change run.
- Long text does not block the main actor noticeably.
- Manual focus test confirms typing remains in the source app.

## Dependencies

- Universal clipboard rewrite fallback.
- Pasteboard helper for Undo.
