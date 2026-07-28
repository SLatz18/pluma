import SwiftUI

@main
struct RewriteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = RewriteViewModel()
    @StateObject private var autocomplete = AutocompleteCoordinator()

    var body: some Scene {
        WindowGroup("Rewrite", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(autocomplete)
        }
        .defaultSize(width: 840, height: 740)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)

        MenuBarExtra("Rewrite", systemImage: "character.cursor.ibeam") {
            AutocompleteMenuBarView()
                .environmentObject(autocomplete)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

private struct AutocompleteMenuBarView: View {
    @EnvironmentObject private var autocomplete: AutocompleteCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Rewrite") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Toggle("Autocomplete as I type", isOn: $autocomplete.isEnabled)
            .toggleStyle(.checkbox)

        Divider()

        Button("Quit Rewrite") {
            NSApp.terminate(nil)
        }
    }
}
