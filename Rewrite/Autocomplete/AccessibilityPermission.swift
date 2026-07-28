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

    // AXIsProcessTrustedWithOptions crashes inside HIServices on macOS 26 when
    // handed a Swift-bridged options dictionary, so the system prompt is
    // skipped; the settings deep link plus polling covers the grant flow.
    func refreshAfterRequest() {
        refresh()
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
