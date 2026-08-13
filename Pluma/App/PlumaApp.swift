import SwiftUI

@main
struct PlumaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: RewriteViewModel
    @StateObject private var autocomplete: AutocompleteCoordinator
    @StateObject private var selectionRewrite: SelectionRewriteController
    @StateObject private var clipboardRewrite: ClipboardRewriteController
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
        _clipboardRewrite = StateObject(wrappedValue: ClipboardRewriteController(overlay: overlay))
        _dictation = StateObject(wrappedValue: DictationController(overlay: overlay))
        _developer = StateObject(wrappedValue: DeveloperMode(overlay: overlay))
    }

    var body: some Scene {
        WindowGroup("pluma", id: "main") {
            MainWindowView()
                .environmentObject(model)
                .environmentObject(autocomplete)
                .environmentObject(selectionRewrite)
                .environmentObject(clipboardRewrite)
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
                .environmentObject(clipboardRewrite)
                .environmentObject(dictation)
                .environmentObject(developer)
                .environmentObject(MemoryStore.shared)
                .environmentObject(SpellMemoryStore.shared)
                .environmentObject(StyleProfileStore.shared)
        }
    }
}

private struct AutocompleteMenuBarView: View {
    @EnvironmentObject private var autocomplete: AutocompleteCoordinator
    @EnvironmentObject private var dictation: DictationController
    @Environment(\.openWindow) private var openWindow

    // A native menu renders its own type, so the rounded-title language
    // arrives here through iconography instead: each row wears its feature's
    // own symbol — the same ones the main window's cards lead with — tinted
    // with the feature colour where the menu honours it.
    var body: some View {
        Button {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label("Open pluma", systemImage: "macwindow")
        }

        Divider()

        Toggle(isOn: $autocomplete.isEnabled) {
            Label(
                "Autocomplete as I type",
                systemImage: FeatureDefinition.autocomplete.symbolName
            )
            .tint(FeatureDefinition.autocomplete.tint.color)
        }
        .toggleStyle(.checkbox)

        Toggle(isOn: $dictation.isEnabled) {
            Label(
                "Dictate with \(dictation.shortcut.display)",
                systemImage: FeatureDefinition.dictation.symbolName
            )
            .tint(FeatureDefinition.dictation.tint.color)
        }
        .toggleStyle(.checkbox)

        Divider()

        Button {
            NSWorkspace.shared.open(DebugLog.url)
        } label: {
            Label("Open Diagnostics Log", systemImage: "doc.text.magnifyingglass")
        }

        Button("Quit pluma") {
            NSApp.terminate(nil)
        }
    }
}
