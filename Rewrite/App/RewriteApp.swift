import SwiftUI

@main
struct RewriteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = RewriteViewModel()

    var body: some Scene {
        WindowGroup("Rewrite") {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: 840, height: 740)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
