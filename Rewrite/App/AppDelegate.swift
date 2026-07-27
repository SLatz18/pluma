import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var serviceProvider: RewriteServiceProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let provider = RewriteServiceProvider()
        serviceProvider = provider
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()
    }
}
