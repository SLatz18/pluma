import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var serviceProvider: RewriteServiceProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let provider = RewriteServiceProvider()
        serviceProvider = provider
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()

        // Universal flow (issue #12): copy text anywhere, press the global
        // hotkey, paste the correction. Sandbox-legal via Carbon hotkeys.
        GlobalHotkey.shared.register {
            ClipboardRewriteController.shared.handleHotkey()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotkey.shared.unregister()
    }
}
