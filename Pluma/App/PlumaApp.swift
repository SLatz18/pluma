import SwiftUI

@main
struct PlumaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: RewriteViewModel
    @StateObject private var autocomplete: AutocompleteCoordinator
    @StateObject private var selectionRewrite: SelectionRewriteController
    @StateObject private var clipboardRewrite: ClipboardRewriteController
    @StateObject private var dictation: DictationController
    @StateObject private var reader: ReaderController
    @StateObject private var developer: DeveloperMode
    @StateObject private var openAICredentials: OpenAICredentials

    init() {
        Preferences.migrateShortcutDefaultsIfNeeded()
        // A clean exit always clears our mapping, so finding it at launch means
        // the last run died. Reset to a known-good keyboard before anything
        // else: drop only our entry (never the user's other remaps) and clear a
        // Caps Lock the crash may have stranded on. The expander re-applies
        // moments later if the feature is still enabled.
        if CapsLockHIDRemap.isOurMappingPresent() {
            try? CapsLockHIDRemap.clearOurMapping()
            CapsLockState.turnOff()
        }

        // One overlay panel for ghost text, rewrite status, dictation, and
        // reader, so they can never stack on top of each other at the caret.
        let overlay = SuggestionOverlayController()
        let rewriteFeedback = RewriteFeedbackController()
        _model = StateObject(wrappedValue: RewriteViewModel())
        _autocomplete = StateObject(wrappedValue: AutocompleteCoordinator(overlay: overlay))
        _selectionRewrite = StateObject(
            wrappedValue: SelectionRewriteController(overlay: overlay, feedback: rewriteFeedback)
        )
        _clipboardRewrite = StateObject(
            wrappedValue: ClipboardRewriteController(overlay: overlay, feedback: rewriteFeedback)
        )
        _dictation = StateObject(wrappedValue: DictationController(overlay: overlay))
        _reader = StateObject(wrappedValue: ReaderController(overlay: overlay))
        _developer = StateObject(wrappedValue: DeveloperMode(overlay: overlay))
        _openAICredentials = StateObject(wrappedValue: OpenAICredentials.forCurrentProcess())

        CapsLockExpander.shared.startMonitoring()
    }

    // There is deliberately no `Settings` scene: the main window's sidebar
    // carries the settings pages, so one surface holds every control. ⌘, and
    // the menu bar's Settings… route there instead of opening a second window.
    // `Window` (not `WindowGroup`) keeps it a true single window — openWindow
    // raises the existing one and File → New Window disappears.
    var body: some Scene {
        Window("pluma", id: "main") {
            MainWindowView()
                .environmentObject(model)
                .environmentObject(autocomplete)
                .environmentObject(selectionRewrite)
                .environmentObject(clipboardRewrite)
                .environmentObject(dictation)
                .environmentObject(reader)
                .environmentObject(developer)
                .environmentObject(openAICredentials)
                .environmentObject(MemoryStore.shared)
                .environmentObject(SpellMemoryStore.shared)
                .environmentObject(StyleProfileStore.shared)
                .environmentObject(CapsLockExpander.shared)
        }
        .defaultSize(width: 980, height: 700)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appSettings) {
                OpenSettingsPageCommand()
            }
        }

        MenuBarExtra("pluma", systemImage: "character.cursor.ibeam") {
            PlumaMenuBarView()
                .environmentObject(autocomplete)
                .environmentObject(dictation)
                .environmentObject(reader)
                .environmentObject(developer)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// The app-menu Settings… item (⌘,). Opens the main window on the General
/// settings page — settings live in the sidebar, not in a second window.
private struct OpenSettingsPageCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") {
            MainNavigation.shared.navigate(to: .general)
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}

private struct PlumaMenuBarView: View {
    @EnvironmentObject private var autocomplete: AutocompleteCoordinator
    @EnvironmentObject private var dictation: DictationController
    @EnvironmentObject private var reader: ReaderController
    @EnvironmentObject private var developer: DeveloperMode
    @Environment(\.openWindow) private var openWindow

    // A native menu renders its own type, so the rounded-title language
    // arrives here through iconography instead: each row wears its feature's
    // own symbol — the same ones the main window's cards lead with — tinted
    // with the feature colour where the menu honours it. Row titles are the
    // canonical FeatureDefinition names, with the shortcut as a parenthetical
    // hint, so the menu and the feature pages describe one thing one way.
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
                FeatureDefinition.autocomplete.name,
                systemImage: FeatureDefinition.autocomplete.symbolName
            )
            .tint(FeatureDefinition.autocomplete.tint.color)
        }
        .toggleStyle(.checkbox)

        Toggle(isOn: $dictation.isEnabled) {
            Label(
                "\(FeatureDefinition.dictation.name) (\(dictation.shortcut.display))",
                systemImage: FeatureDefinition.dictation.symbolName
            )
            .tint(FeatureDefinition.dictation.tint.color)
        }
        .toggleStyle(.checkbox)

        Toggle(isOn: $reader.isEnabled) {
            Label(
                "\(FeatureDefinition.reader.name) (\(reader.shortcut.display))",
                systemImage: FeatureDefinition.reader.symbolName
            )
            .tint(FeatureDefinition.reader.tint.color)
        }
        .toggleStyle(.checkbox)

        Divider()

        if developer.isUnlocked {
            Button {
                NSWorkspace.shared.open(DebugLog.url)
            } label: {
                Label("Open Diagnostics Log", systemImage: "doc.text.magnifyingglass")
            }
        }

        // The app runs as an accessory with no main menu when every window is
        // closed, so without this row Settings would be unreachable from a
        // cold start.
        Button {
            MainNavigation.shared.navigate(to: .general)
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label("Settings…", systemImage: "gear")
        }

        Button("Quit pluma") {
            NSApp.terminate(nil)
        }
    }
}
