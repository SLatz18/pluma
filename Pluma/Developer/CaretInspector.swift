import AppKit
import ApplicationServices

struct CaretReadout: Equatable {
    let appName: String
    let role: String
    let caretLocation: Int
    let caret: CaretGeometry?
    let fieldFrame: CGRect?
    let fontSize: CGFloat?
    let widthBudget: CGFloat?
    let eligibility: GhostTextEligibility
    let capturedAt: Date

    var allowsGhostText: Bool {
        guard let caret else { return false }
        return eligibility.allows(caret)
    }

    // The reason ghost text was refused, which is the question the inspector
    // exists to answer.
    var verdict: String {
        guard let caret else { return "No caret geometry — chip at the field edge" }
        if eligibility.isRightToLeft { return "Refused: right-to-left line" }
        if allowsGhostText {
            return caret.isPrecise
                ? "Ghost text allowed"
                : "Ghost text allowed (line-level caret implies end of line)"
        }
        return "Refused: caret is not at the end of the text"
    }
}

/// Polls the focused field so the Dev page can show what the ghost-text code is
/// actually seeing.
///
/// Runs **only while the Dev page is on screen** — `start()` from `.onAppear`,
/// `stop()` from `.onDisappear`. At rest it holds no timer, so navigating away,
/// closing the window, or locking developer mode all end the Accessibility
/// round trips immediately.
@MainActor
final class CaretInspector: ObservableObject {
    @Published private(set) var readout: CaretReadout?

    private var timer: Timer?
    private let interval: TimeInterval = 0.25
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    var onSample: ((CaretGeometry?) -> Void)?

    func start() {
        guard timer == nil else { return }
        sample()
        // Built unscheduled and added once in .common mode — `scheduledTimer`
        // would already have registered it in .default, and adding it twice
        // makes it fire twice per tick.
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sample()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        onSample?(nil)
    }

    private func sample() {
        guard let element = AXFocus.focusedElement() else { return }

        // While you are reading the Dev page, pluma is frontmost and the
        // focused element is our own. Keep the last field from another app
        // instead — that is the one being debugged.
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid != ownPID else { return }

        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? "unknown"

        var textValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue)
        let text = textValue as? String

        guard let location = Self.caretLocation(of: element) else { return }

        let caret = FocusedFieldTracker.caretGeometry(for: element, location: location)
        let fieldFrame = FocusedFieldTracker.frame(of: element)
        let eligibility = text.map { GhostTextEligibility.of(text: $0, caretLocation: location) }
            ?? .unknown

        readout = CaretReadout(
            appName: NSRunningApplication(processIdentifier: pid)?.localizedName ?? "unknown",
            role: role,
            caretLocation: location,
            caret: caret,
            fieldFrame: fieldFrame,
            fontSize: caret.map { GhostTextGeometry.fontSize(forCaretHeight: $0.rect.height) },
            widthBudget: caret.map {
                GhostTextGeometry.widthBudget(
                    caretMaxX: $0.rect.maxX,
                    fieldMaxX: fieldFrame?.maxX,
                    screenMaxX: NSScreen.main?.visibleFrame.maxX ?? $0.rect.maxX
                )
            },
            eligibility: eligibility,
            capturedAt: .now
        )
        onSample?(caret)
    }

    private static func caretLocation(of element: AXUIElement) -> Int? {
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
        return range.location
    }
}
