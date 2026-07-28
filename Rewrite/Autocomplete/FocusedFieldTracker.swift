import AppKit
import ApplicationServices

struct FocusedFieldSnapshot {
    let element: AXUIElement
    let text: String
    let caretLocation: Int
    let caretScreenPoint: CGPoint?

    var textBeforeCaret: String {
        let nsText = text as NSString
        guard caretLocation <= nsText.length else { return text }
        return nsText.substring(to: caretLocation)
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

    private static let textRoles: Set<String> = ["AXTextArea", "AXTextField"]

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
        guard let element, let snapshot = Self.makeSnapshot(from: element) else {
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

    private static func makeSnapshot(from element: AXUIElement) -> FocusedFieldSnapshot? {
        var textValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue) == .success,
            let text = textValue as? String
        else { return nil }

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

        guard selection.length == 0, selection.location == (text as NSString).length else {
            return nil
        }

        return FocusedFieldSnapshot(
            element: element,
            text: text,
            caretLocation: selection.location,
            caretScreenPoint: caretPoint(for: element, location: selection.location)
        )
    }

    private static func caretPoint(for element: AXUIElement, location: Int) -> CGPoint? {
        var caretRange = CFRange(location: location, length: 0)
        guard
            let rangeValue = AXValueCreate(.cfRange, &caretRange)
        else { return nil }

        var boundsValue: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                rangeValue,
                &boundsValue
            ) == .success,
            let boundsValue,
            CFGetTypeID(boundsValue) == AXValueGetTypeID()
        else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }
        return CGPoint(x: rect.maxX + 4, y: rect.minY)
    }
}
