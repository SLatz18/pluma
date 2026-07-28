import AppKit
import ApplicationServices

@MainActor
final class AccessibilityPermission {
    static let shared = AccessibilityPermission()

    private(set) var isTrusted: Bool
    private var monitorTask: Task<Void, Never>?

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

    func requestPrompt() {
        // String literal avoids the non-Sendable kAXTrustedCheckOptionPrompt global.
        let options = ["AXTrustedCheckOption": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted != isTrusted {
            isTrusted = trusted
            onChange?(trusted)
        }
    }

    func openSystemSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        else { return }
        NSWorkspace.shared.open(url)
    }

    func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }
}
