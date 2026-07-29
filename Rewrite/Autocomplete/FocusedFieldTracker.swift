import AppKit
import ApplicationServices

struct FocusedFieldSnapshot {
    let element: AXUIElement
    let text: String
    let caretLocation: Int
    let caret: CaretGeometry?

    var textBeforeCaret: String {
        let nsText = text as NSString
        guard caretLocation <= nsText.length else { return text }
        return nsText.substring(to: caretLocation)
    }

    var ghostEligibility: GhostTextEligibility {
        .of(text: text, caretLocation: caretLocation)
    }
}

@MainActor
final class FocusedFieldTracker {
    var onSnapshot: ((FocusedFieldSnapshot?) -> Void)?

    private var appObserver: AXObserver?
    private var observedPID: pid_t = 0
    private var observedElement: AXUIElement?
    private var frontmostObserver: NSObjectProtocol?
    private var running = false

    // ComboBox covers rich web composers like Slack's, which report the
    // editable role as AXComboBox while still exposing value + selection.
    private static let textRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox"]

    func start() {
        guard !running else { return }
        running = true

        frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.attachToFrontmostApp()
            }
        }
        attachToFrontmostApp()
    }

    func stop() {
        running = false
        if let frontmostObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(frontmostObserver)
        }
        frontmostObserver = nil
        detachFromApp()
        onSnapshot?(nil)
    }

    // Chromium/Electron apps only build their accessibility tree after an
    // assistive client asks for it; these attributes are that ask.
    private static func nudgeAccessibilityTree(for appElement: AXUIElement) {
        for attribute in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
            AXUIElementSetAttributeValue(appElement, attribute as CFString, kCFBooleanTrue)
        }
    }

    func reResolveFocus() {
        focusChanged()
    }

    private func attachToFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }

        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            detachFromApp()
            onSnapshot?(nil)
            return
        }

        DebugLog.log("attach: \(app.localizedName ?? app.bundleIdentifier ?? "?")")

        guard app.processIdentifier != observedPID else {
            focusChanged()
            return
        }

        detachFromApp()

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let tracker = Unmanaged<FocusedFieldTracker>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated {
                tracker.handleAXNotification(notification as String, element: element)
            }
        }
        guard AXObserverCreate(app.processIdentifier, callback, &observer) == .success,
              let observer
        else { return }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        Self.nudgeAccessibilityTree(for: appElement)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(
            observer, appElement,
            kAXFocusedUIElementChangedNotification as CFString, refcon
        )

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        appObserver = observer
        observedPID = app.processIdentifier
        focusChanged()
    }

    private func detachFromApp() {
        if let appObserver {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(appObserver),
                .defaultMode
            )
        }
        appObserver = nil
        observedPID = 0
        observedElement = nil
    }

    private func handleAXNotification(_ notification: String, element: AXUIElement) {
        switch notification {
        case kAXFocusedUIElementChangedNotification:
            focusChanged()
        case kAXValueChangedNotification, kAXSelectedTextChangedNotification:
            publishSnapshot(from: element)
        default:
            break
        }
    }

    private func focusChanged() {
        guard observedPID != 0 else { return }
        let appElement = AXUIElementCreateApplication(observedPID)

        var focusedValue: CFTypeRef?
        let readResult = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue
        )
        guard
            readResult == .success,
            let focusedValue,
            CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else {
            DebugLog.log("no focused element (error \(readResult.rawValue))")
            observedElement = nil
            onSnapshot?(nil)
            return
        }

        let element = focusedValue as! AXUIElement
        guard Self.isEditableTextElement(element) else {
            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
            DebugLog.log("focused element not text: \(roleValue as? String ?? "?")")
            observedElement = nil
            onSnapshot?(nil)
            return
        }

        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        DebugLog.log("focused text element: \(roleValue as? String ?? "?")")

        guard let appObserver else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(
            appObserver, element,
            kAXValueChangedNotification as CFString, refcon
        )
        AXObserverAddNotification(
            appObserver, element,
            kAXSelectedTextChangedNotification as CFString, refcon
        )

        observedElement = element
        publishSnapshot(from: element)
    }

    private func publishSnapshot(from element: AXUIElement?) {
        guard let element, let snapshot = makeSnapshot(from: element) else {
            onSnapshot?(nil)
            return
        }
        onSnapshot?(snapshot)
    }

    private static func isEditableTextElement(_ element: AXUIElement) -> Bool {
        var roleValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
            let role = roleValue as? String,
            textRoles.contains(role)
        else { return false }

        var subroleValue: CFTypeRef?
        if
            AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue) == .success,
            let subrole = subroleValue as? String,
            subrole == "AXSecureTextField"
        {
            return false
        }
        return true
    }

    private var lastLoggedRejection: String?

    private func logRejection(_ reason: String) {
        guard reason != lastLoggedRejection else { return }
        lastLoggedRejection = reason
        DebugLog.log("snapshot rejected: \(reason)", at: .verbose)
    }

    private func makeSnapshot(from element: AXUIElement) -> FocusedFieldSnapshot? {
        var textValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue) == .success,
            let text = textValue as? String
        else {
            logRejection("no string value")
            return nil
        }

        var rangeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, &rangeValue
            ) == .success,
            let rangeValue,
            CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else {
            logRejection("no selection range")
            return nil
        }

        var selection = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &selection) else {
            logRejection("unreadable selection range")
            return nil
        }

        guard selection.length == 0 else {
            logRejection("selection not empty (\(selection.length) chars)")
            return nil
        }
        guard selection.location > 0 else {
            logRejection("caret at start")
            return nil
        }

        lastLoggedRejection = nil
        return FocusedFieldSnapshot(
            element: element,
            text: text,
            caretLocation: selection.location,
            caret: Self.caretGeometry(for: element, location: selection.location)
        )
    }

    // Reads the field's text up to the caret; used to re-sync state to field
    // truth after insertions instead of assuming what landed.
    static func readPrefix(of element: AXUIElement) -> String? {
        var textValue: CFTypeRef?
        var rangeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue) == .success,
            let text = textValue as? String,
            AXUIElementCopyAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, &rangeValue
            ) == .success,
            let rangeValue,
            CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else { return nil }

        var selection = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &selection) else { return nil }
        let nsText = text as NSString
        guard selection.location <= nsText.length else { return nil }
        return nsText.substring(to: selection.location)
    }

    // Caret geometry from Chromium fields is unreliable — end-of-text carets
    // report a degenerate rect at the screen's bottom-left corner — so this
    // runs a ladder of probes rather than a single query. See CaretResolver.
    static func caretGeometry(for element: AXUIElement, location: Int) -> CaretGeometry? {
        let caret = CaretResolver.resolve(location: location, using: AXCaretProbe(element: element))
        // Autoclosure: at anything below verbose this whole string, and the
        // rect formatting inside it, is never built. It runs per keystroke.
        if let caret {
            DebugLog.log(
                "caret at \(location) via \(caret.source.title): \(Self.describe(caret.rect))",
                at: .verbose
            )
        } else {
            DebugLog.log("no caret geometry at \(location); falling back to the field", at: .verbose)
        }
        return caret
    }

    static func describe(_ rect: CGRect) -> String {
        "x \(Int(rect.minX)) y \(Int(rect.minY)) \(Int(rect.width))×\(Int(rect.height))"
    }

    // Where to put a chip when no probe could find the caret. Chromium-based
    // fields expose no caret geometry, but their own frame is still available,
    // and the bottom edge of a text field sits near the line being typed into.
    static func fieldEdgeAnchor(for element: AXUIElement) -> CGPoint? {
        guard let frame = frame(of: element), isPlausibleField(frame) else { return nil }
        DebugLog.log("anchoring inside field \(frame)", at: .verbose)
        // A tall field is a terminal or a text area, where the line being typed
        // is the last one, so sit just inside the bottom edge. A short field is
        // a one-liner, so sit just above it and clear of the text.
        // Deliberately no clamping to the primary screen: a field can live on a
        // display above or left of it, at negative coordinates.
        let y = frame.height >= 60 ? frame.maxY - 34 : frame.minY - 30
        return CGPoint(x: frame.minX + 8, y: y)
    }

    // Chromium apps put keyboard focus on a hidden proxy input a few points
    // across rather than on the visible text box, so a frame that small is a
    // decoy and drawing next to it is worse than not drawing at all.
    private static func isPlausibleField(_ frame: CGRect) -> Bool {
        frame.width >= 60 && frame.height >= 14
    }

    // Nonisolated because AXCaretProbe reads it from outside the main actor;
    // it is a pure Accessibility round trip and touches no tracker state.
    nonisolated static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
            let positionValue, let sizeValue,
            CFGetTypeID(positionValue) == AXValueGetTypeID(),
            CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }
}
