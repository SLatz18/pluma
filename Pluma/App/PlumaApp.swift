import SwiftUI

@main
struct PlumaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: RewriteViewModel
    @StateObject private var autocomplete: AutocompleteCoordinator
    @StateObject private var selectionRewrite: SelectionRewriteController
    @StateObject private var dictation: DictationController
    @StateObject private var developer: DeveloperMode

    init() {
        Preferences.migrateShortcutDefaultsIfNeeded()

        // One overlay panel for ghost text, rewrite status, and the dictation
        // HUD, so they can never stack on top of each other at the caret.
        let overlay = SuggestionOverlayController()
        _model = StateObject(wrappedValue: RewriteViewModel())
        _autocomplete = StateObject(wrappedValue: AutocompleteCoordinator(overlay: overlay))
        _selectionRewrite = StateObject(wrappedValue: SelectionRewriteController(overlay: overlay))
        _dictation = StateObject(wrappedValue: DictationController(overlay: overlay))
        _developer = StateObject(wrappedValue: DeveloperMode(overlay: overlay))
    }

    var body: some Scene {
        WindowGroup("pluma", id: "main") {
            MainWindowView()
                .environmentObject(model)
                .environmentObject(autocomplete)
                .environmentObject(selectionRewrite)
                .environmentObject(dictation)
                .environmentObject(developer)
        }
        .defaultSize(width: 980, height: 700)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)

        MenuBarExtra("pluma", systemImage: "character.cursor.ibeam") {
            AutocompleteMenuBarView()
                .environmentObject(autocomplete)
                .environmentObject(dictation)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(autocomplete)
                .environmentObject(developer)
                .environmentObject(MemoryStore.shared)
                .environmentObject(StyleProfileStore.shared)
        }
    }
}

private struct AutocompleteMenuBarView: View {
    @EnvironmentObject private var autocomplete: AutocompleteCoordinator
    @EnvironmentObject private var dictation: DictationController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open pluma") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Toggle("Autocomplete as I type", isOn: $autocomplete.isEnabled)
            .toggleStyle(.checkbox)

        Toggle("Dictate with \(dictation.shortcut.display)", isOn: $dictation.isEnabled)
            .toggleStyle(.checkbox)

        Divider()

        Button("Open Diagnostics Log") {
            NSWorkspace.shared.open(DebugLog.url)
        }

        Button("Quit pluma") {
            NSApp.terminate(nil)
        }
    }
}
