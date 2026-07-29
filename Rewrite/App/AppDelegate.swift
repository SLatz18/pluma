import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var serviceProvider: RewriteServiceProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let provider = RewriteServiceProvider()
        serviceProvider = provider
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()

        // Dock presence follows window visibility: LSUIElement starts us as an
        // accessory (menu bar only), a key window upgrades to .regular, and
        // closing the last one drops back. NSPanel is excluded so the overlay
        // pill never summons a Dock icon; minimized windows still count as
        // open, since that's where they live.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowVisibilityChanged(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowVisibilityChanged(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        ClipboardHotkeyManager.shared.start {
            ClipboardRewriteController.shared.handleHotkey()
        }

        if ClipboardHotkeyManager.shared.status == .unavailable {
            HUDWindowController.shared.showHint(HotkeyStatus.unavailable.detail)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        updateActivationPolicy()
    }

    @objc private func windowVisibilityChanged(_ notification: Notification) {
        // During willClose the window still reports isVisible, so let the
        // close settle before counting.
        DispatchQueue.main.async { [weak self] in
            self?.updateActivationPolicy()
        }
    }

    private func updateActivationPolicy() {
        // Only normal-level app windows count: the menu bar status item's
        // NSStatusBarWindow is always visible at .statusBar level, and the
        // overlay pill is an NSPanel — both would pin us to .regular forever.
        let hasOpenWindow = NSApp.windows.contains { window in
            !(window is NSPanel) && window.level == .normal
                && (window.isVisible || window.isMiniaturized)
        }
        NSApp.setActivationPolicy(hasOpenWindow ? .regular : .accessory)
    }

    // Autocomplete keeps working from the menu bar after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardHotkeyManager.shared.stop()
    }

    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        ClipboardHotkeyManager.shared.refresh()
    }
}
