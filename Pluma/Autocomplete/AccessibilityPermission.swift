import AppKit
import ApplicationServices

@MainActor
final class AccessibilityPermission {
    static let shared = AccessibilityPermission()

    private(set) var isTrusted: Bool
    private let poller = PermissionPoller()

    var onChange: ((Bool) -> Void)?

    init() {
        isTrusted = AXIsProcessTrusted()
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        guard trusted != isTrusted else { return }
        isTrusted = trusted
        onChange?(trusted)
    }

    // The prompt lives in an Objective-C helper: AXIsProcessTrustedWithOptions
    // segfaults inside HIServices on macOS 26 when handed a Swift-bridged
    // options dictionary, and calling it is also what registers the app in the
    // Accessibility settings list.
    func requestPrompt() {
        let trusted = PlumaRequestAccessibilityPrompt()
        if trusted != isTrusted {
            isTrusted = trusted
            onChange?(trusted)
        }
    }

    func openSystemSettings() {
        PrivacySettingsPane.open("Privacy_Accessibility")
    }

    func startMonitoring() {
        poller.start { [weak self] in self?.refresh() }
    }
}
