import AppKit
import CoreGraphics
import Foundation

struct HotkeyStatus: Equatable, Sendable {
    enum Tier: Equatable, Sendable {
        case unavailable
        case carbonOnly
        case enhanced
    }

    let tier: Tier
    let title: String
    let detail: String
    let symbolName: String

    static let unavailable = HotkeyStatus(
        tier: .unavailable,
        title: "Hotkey unavailable",
        detail: "Another app may be using Control-Option-Shift-Command-E.",
        symbolName: "exclamationmark.triangle"
    )

    static let carbonOnly = HotkeyStatus(
        tier: .carbonOnly,
        title: "Standard hotkey",
        detail: "Works in most apps. Enable Input Monitoring for Google Docs and Electron apps.",
        symbolName: "keyboard"
    )

    static let enhanced = HotkeyStatus(
        tier: .enhanced,
        title: "Enhanced hotkey",
        detail: "Input Monitoring is on, so the hotkey works even when apps consume the key first.",
        symbolName: "keyboard.badge.ellipsis"
    )
}

@MainActor
final class ClipboardHotkeyManager: ObservableObject {
    static let shared = ClipboardHotkeyManager()

    @Published private(set) var status: HotkeyStatus = .carbonOnly
    private var debouncer = HotkeyDebouncer()
    private var action: (() -> Void)?

    private init() {}

    func start(action: @escaping () -> Void) {
        self.action = action
        refresh()
    }

    func refresh() {
        guard let action else { return }

        let carbonRegistered = GlobalHotkey.shared.register { [weak self] in
            self?.fire(action)
        }

        guard carbonRegistered else {
            InputMonitoringHotkey.shared.stop()
            status = .unavailable
            return
        }

        if CGPreflightListenEventAccess() {
            InputMonitoringHotkey.shared.start { [weak self] in
                self?.fire(action)
            }
            status = InputMonitoringHotkey.shared.isActive ? .enhanced : .carbonOnly
        } else {
            InputMonitoringHotkey.shared.stop()
            status = .carbonOnly
        }
    }

    func requestInputMonitoringAccess() {
        _ = CGRequestListenEventAccess()
        openInputMonitoringSettings()
    }

    func openInputMonitoringSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent"
            )
        else { return }
        NSWorkspace.shared.open(url)
    }

    func stop() {
        GlobalHotkey.shared.unregister()
        InputMonitoringHotkey.shared.stop()
        action = nil
        status = .carbonOnly
    }

    private func fire(_ action: () -> Void) {
        guard debouncer.shouldFire() else { return }
        action()
    }
}
