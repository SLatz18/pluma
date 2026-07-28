import AppKit
import ApplicationServices

@MainActor
final class SelectionRewriteController: ObservableObject {
    @Published private(set) var shortcut: GlobalShortcut
    @Published private(set) var isWorking = false

    private let defaults: UserDefaults
    private let hotkey = HotkeyManager()
    private let overlay = SuggestionOverlayController()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shortcut = Preferences.globalShortcut(from: defaults)
        hotkey.onHotKey = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.rewriteSelection()
            }
        }
        hotkey.register(shortcut)
    }

    func recordShortcut(_ newShortcut: GlobalShortcut) {
        shortcut = newShortcut
        Preferences.saveGlobalShortcut(newShortcut, to: defaults)
        hotkey.register(newShortcut)
    }

    private func rewriteSelection() async {
        guard !isWorking else { return }

        guard AccessibilityPermission.shared.isTrusted else {
            flash(systemImage: "hand.raised", message: "Rewrite needs Accessibility access")
            return
        }

        guard
            let element = Self.focusedElement(),
            let selectedText = Self.selectedText(of: element),
            !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            flash(systemImage: "text.cursor", message: "Select some text first")
            return
        }

        isWorking = true
        defer { isWorking = false }

        let anchor = Self.selectionAnchor(of: element) ?? Self.mouseAnchor()
        overlay.show(
            content: StatusOverlayView(systemImage: "sparkles", message: "Rewriting…"),
            atTopLeftPoint: anchor
        )

        do {
            let output = try await RewriteRunner.rewrite(
                provider: Preferences.provider(from: defaults),
                intent: Preferences.intent(from: defaults),
                text: selectedText,
                ollamaModel: Preferences.ollamaModel(from: defaults)
            )
            if AXTextInsertion.insert(output, into: element) {
                overlay.hide()
            } else {
                flash(systemImage: "exclamationmark.triangle", message: "This field rejected the edit")
            }
        } catch {
            flash(systemImage: "exclamationmark.triangle", message: error.localizedDescription)
        }
    }

    private func flash(systemImage: String, message: String) {
        overlay.show(
            content: StatusOverlayView(systemImage: systemImage, message: message),
            atTopLeftPoint: Self.mouseAnchor()
        )
        Task { [overlay] in
            try? await Task.sleep(for: .seconds(2.5))
            overlay.hide()
        }
    }

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue
            ) == .success,
            let focusedValue,
            CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else { return nil }
        return (focusedValue as! AXUIElement)
    }

    private static func selectedText(of element: AXUIElement) -> String? {
        var selectedValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXSelectedTextAttribute as CFString, &selectedValue
            ) == .success
        else { return nil }
        return selectedValue as? String
    }

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

        var anchorRange = CFRange(location: selection.location, length: 0)
        guard let anchorRangeValue = AXValueCreate(.cfRange, &anchorRange) else { return nil }

        var boundsValue: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                anchorRangeValue,
                &boundsValue
            ) == .success,
            let boundsValue,
            CFGetTypeID(boundsValue) == AXValueGetTypeID()
        else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }
        return CGPoint(x: rect.minX, y: rect.maxY + 6)
    }

    // NSEvent.mouseLocation is Cocoa bottom-left-origin; AX/overlay coordinates
    // are top-left-origin on the primary display.
    private static func mouseAnchor() -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? mouse.y
        return CGPoint(x: mouse.x + 8, y: primaryHeight - mouse.y + 12)
    }
}
