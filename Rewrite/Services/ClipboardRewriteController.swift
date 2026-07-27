import AppKit
import Foundation

/// Implements the sandbox-legal universal flow (issue #12):
/// user copies text (Cmd+C), presses the global hotkey, the clipboard's
/// text is rewritten in place, and the user pastes (Cmd+V).
/// Works in apps where Services pasteback is unavailable (e.g. Google Docs).
@MainActor
final class ClipboardRewriteController {
    static let shared = ClipboardRewriteController()

    private var isRewriting = false
    private var lastSnapshot: PasteboardSnapshot?
    private var lastResult: String?
    private var lastResultChangeCount: Int?

    private init() {}

    func handleHotkey() {
        let pasteboard = NSPasteboard.general

        guard !isRewriting else {
            HUDWindowController.shared.showHint("Rewrite is already working.")
            return
        }

        let originalChangeCount = pasteboard.changeCount
        let originalSnapshot = PasteboardSnapshot(pasteboard)
        guard
            pasteboard.changeCount == originalChangeCount,
            let source = pasteboard.string(forType: .string),
            let envelope = TextEnvelope(source),
            pasteboard.changeCount == originalChangeCount
        else {
            HUDWindowController.shared.showHint("Copy some text first, then press the hotkey.")
            return
        }

        // Clipboard still holds our previous result — the user probably
        // pressed the hotkey again without copying new text.
        if source == lastResult, pasteboard.changeCount == lastResultChangeCount {
            HUDWindowController.shared.showHint("Already rewrote this. Copy new text first.")
            return
        }

        isRewriting = true
        HUDWindowController.shared.showHint("Rewriting copied text…")

        let provider = Preferences.provider(from: .standard)
        let intent = Preferences.intent(from: .standard)
        let ollamaModel = Preferences.ollamaModel(from: .standard)

        Task {
            defer { isRewriting = false }
            do {
                let output = try await RewriteRunner.rewrite(
                    provider: provider,
                    intent: intent,
                    text: envelope.body,
                    ollamaModel: ollamaModel
                )
                let revisedText = try envelope.replacingBody(with: output)

                guard pasteboard.changeCount == originalChangeCount else {
                    throw RewriteEngineError.clipboardChanged
                }

                guard revisedText != source else {
                    HUDWindowController.shared.showHint("Looks good already — no changes needed.")
                    return
                }

                guard PasteboardSnapshot.replaceString(
                    revisedText,
                    on: pasteboard,
                    rollbackTo: originalSnapshot
                ) else {
                    throw RewriteEngineError.invalidResponse
                }

                lastSnapshot = originalSnapshot
                lastResult = revisedText
                lastResultChangeCount = pasteboard.changeCount
                HUDWindowController.shared.showResult(
                    original: source,
                    revised: revisedText,
                    intent: intent
                )
            } catch {
                HUDWindowController.shared.showHint(error.localizedDescription)
            }
        }
    }

    /// Restores the pre-rewrite text to the clipboard.
    @discardableResult
    func undo() -> Bool {
        let pasteboard = NSPasteboard.general
        guard
            let lastSnapshot,
            let currentResult = lastResult,
            pasteboard.changeCount == lastResultChangeCount,
            pasteboard.string(forType: .string) == currentResult,
            pasteboard.changeCount == lastResultChangeCount
        else {
            return false
        }

        guard lastSnapshot.restore(to: pasteboard) else {
            return false
        }

        self.lastSnapshot = nil
        lastResult = nil
        lastResultChangeCount = nil
        return true
    }
}
