import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var serviceProvider: RewriteServiceProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let provider = RewriteServiceProvider()
        serviceProvider = provider
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()

        // Started here, not as a `@StateObject`, for the reason in the repo's
        // toolchain notes: `@StateObject(wrappedValue:)` autoclosures are lazy,
        // so a controller with no view referencing it would never be built and
        // the hotkey would never register. Mirrors
        // `CapsLockExpander.shared.startMonitoring()`.
        //
        // Skipped in a test host for the same reason the expander is: the unit
        // test bundle is hosted by this app, so `xcodebuild test` would
        // otherwise register ⌃⌥⌘4 in a second process and fight the running
        // instance for the chord. Every other controller is a lazy
        // `@StateObject` that never gets built without a window, so this
        // singleton is the only hotkey owner that would reach a test host.
        if !PlumaApp.isRunningTests {
            ClipboardHistoryController.shared.start()
        }

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
        CapsLockExpander.shared.stopMonitoring()
    }
}
