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
    private var lastOriginal: String?
    private var lastResult: String?
    private var lastResultChangeCount: Int?

    private init() {}

    func handleHotkey() {
        let pasteboard = NSPasteboard.general

        guard
            let source = pasteboard.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !source.isEmpty
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

        guard !isRewriting else {
            HUDWindowController.shared.showHint("Rewrite is already working.")
            return
        }
        isRewriting = true
        let originalChangeCount = pasteboard.changeCount

        let provider = Preferences.provider(from: .standard)
        let intent = Preferences.intent(from: .standard)
        let ollamaModel = Preferences.ollamaModel(from: .standard)

        Task {
            defer { isRewriting = false }
            do {
                let output = try await RewriteRunner.rewrite(
                    provider: provider,
                    intent: intent,
                    text: source,
                    ollamaModel: ollamaModel
                )

                guard pasteboard.changeCount == originalChangeCount else {
                    throw RewriteEngineError.clipboardChanged
                }

                guard output != source else {
                    HUDWindowController.shared.showHint("Looks good already — no changes needed.")
                    return
                }

                lastOriginal = source
                lastResult = output
                pasteboard.clearContents()
                guard pasteboard.setString(output, forType: .string) else {
                    throw RewriteEngineError.invalidResponse
                }
                lastResultChangeCount = pasteboard.changeCount
                HUDWindowController.shared.showResult(
                    original: source,
                    revised: output,
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
            let lastOriginal,
            let currentResult = lastResult,
            pasteboard.changeCount == lastResultChangeCount,
            pasteboard.string(forType: .string) == currentResult
        else {
            return false
        }

        pasteboard.clearContents()
        guard pasteboard.setString(lastOriginal, forType: .string) else {
            return false
        }

        lastResult = lastOriginal
        lastResultChangeCount = pasteboard.changeCount
        self.lastOriginal = nil
        return true
    }
}
