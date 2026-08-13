import AppKit
import ApplicationServices

@MainActor
final class SelectionRewriteController: ObservableObject {
    @Published private(set) var shortcut: GlobalShortcut
    @Published private(set) var isWorking = false
    @Published private(set) var shortcutConflict: String?

    private let defaults: UserDefaults
    private let hotkey = HotkeyManager()
    private let overlay: SuggestionOverlayController
    private let feedback: RewriteFeedbackController

    init(
        defaults: UserDefaults = .standard,
        overlay: SuggestionOverlayController = SuggestionOverlayController(),
        feedback: RewriteFeedbackController = RewriteFeedbackController()
    ) {
        self.defaults = defaults
        self.overlay = overlay
        self.feedback = feedback
        shortcut = Preferences.globalShortcut(from: defaults)
        hotkey.onPress = { [weak self] slot in
            guard slot == .rewriteSelection else { return }
            Task { @MainActor [weak self] in
                await self?.rewriteSelection()
            }
        }
        hotkey.register(shortcut, in: .rewriteSelection)
    }

    func recordShortcut(_ newShortcut: GlobalShortcut) {
        guard let conflict = Preferences.conflictMessage(
            for: newShortcut, ignoring: .rewrite, from: defaults
        ) else {
            shortcutConflict = nil
            shortcut = newShortcut
            Preferences.saveGlobalShortcut(newShortcut, to: defaults)
            hotkey.register(newShortcut, in: .rewriteSelection)
            return
        }
        shortcutConflict = conflict
    }

    private func rewriteSelection() async {
        guard !isWorking else { return }
        DebugLog.log("hotkey fired")

        guard AccessibilityPermission.shared.isTrusted else {
            DebugLog.log("rewrite blocked: not trusted", at: .quiet)
            flash(systemImage: "hand.raised", message: "pluma needs Accessibility access")
            return
        }

        guard
            let element = AXFocus.focusedElement(),
            let selectedText = AXFocus.selectedText(of: element),
            !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            DebugLog.log("rewrite: no focused element with a text selection")
            flash(systemImage: "text.cursor", message: "Select some text first")
            return
        }
        let originalRange = Self.selectedRange(of: element, expectedText: selectedText)

        let chain = Preferences.chain(from: defaults)
        guard !chain.isEmpty else {
            flash(systemImage: "sparkles", message: "Pick a recipe on the Rewrite page first")
            return
        }

        DebugLog.log("rewrite start: \(selectedText.count) chars selected, chain \(chain.count) steps")
        isWorking = true
        defer { isWorking = false }

        let anchor = Self.selectionAnchor(of: element)
            ?? SuggestionOverlayController.mouseTopLeftPoint()
        overlay.show(
            .status(
                systemImage: "sparkles",
                message: "Rewriting…",
                tone: .accent,
                anchor: anchor
            ),
            from: .rewrite
        )

        do {
            let output = try await RewriteRunner.rewriteChain(
                provider: Preferences.provider(from: defaults),
                steps: chain,
                text: selectedText,
                ollamaModel: Preferences.ollamaModel(from: defaults),
                onProgress: { [overlay] progress in
                    guard case .starting(let step, let of, let intent) = progress, of > 1 else { return }
                    overlay.show(
                        .status(
                            systemImage: "sparkles",
                            message: "Rewriting \(step) of \(of) — \(intent.title)…",
                            tone: .accent,
                            anchor: anchor
                        ),
                        from: .rewrite
                    )
                }
            )
            if await AXTextInsertion.insert(output, into: element) {
                DebugLog.log("rewrite inserted OK")
                overlay.hide(from: .rewrite)
                feedback.showResult(
                    original: selectedText,
                    revised: output,
                    pipeline: chain.map(\.title).joined(separator: " → "),
                    destination: "Selection updated",
                    pasteHint: false,
                    onUndo: {
                        guard let originalRange else { return .unavailable }
                        let rewrittenRange = CFRange(
                            location: originalRange.location,
                            length: (output as NSString).length
                        )
                        switch await AXTextInsertion.replaceIfUnchanged(
                            range: rewrittenRange,
                            expectedText: output,
                            with: selectedText,
                            in: element
                        ) {
                        case .replaced:
                            return .restored
                        case .contentChanged:
                            return .contentChanged
                        case .unavailable:
                            return .unavailable
                        }
                    }
                )
            } else {
                DebugLog.log("rewrite insertion failed", at: .quiet)
                flash(
                    systemImage: "exclamationmark.triangle",
                    message: "This field rejected the edit",
                    tone: .failure
                )
            }
        } catch {
            DebugLog.log("rewrite failed: \(error.localizedDescription)", at: .quiet)
            flash(
                systemImage: "exclamationmark.triangle",
                message: error.localizedDescription,
                tone: .failure
            )
        }
    }

    private func flash(
        systemImage: String,
        message: String,
        tone: OverlayTone = .warning
    ) {
        overlay.flashAtMouse(systemImage: systemImage, message: message, tone: tone, from: .rewrite)
    }

    private static func selectedRange(of element: AXUIElement, expectedText: String) -> CFRange? {
        var rangeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, &rangeValue
            ) == .success,
            let rangeValue,
            CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else { return nil }

        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { return nil }
        guard range.length == (expectedText as NSString).length else { return nil }
        return range
    }
    // Just below the start of the selection, so the progress chip never covers
    // the text being rewritten.
    private static func selectionAnchor(of element: AXUIElement) -> CGPoint? {
        var rangeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, &rangeValue
            ) == .success,
            let rangeValue,
            CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else { return nil }

        var selection = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &selection) else { return nil }

        guard
            let caret = FocusedFieldTracker.caretGeometry(for: element, location: selection.location)
        else { return FocusedFieldTracker.fieldEdgeAnchor(for: element) }
        return CGPoint(x: caret.rect.minX, y: caret.rect.maxY + 6)
    }
}
