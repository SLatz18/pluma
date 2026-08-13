import SwiftUI

enum MainPage: String, CaseIterable, Identifiable, Hashable {
    case overview
    case rewrite
    case autocomplete
    case dictation
    case reader
    case general
    case writing
    case privacy
    // Only ever in the sidebar once the cheat code has been entered.
    case developer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .rewrite: "Rewrite"
        case .autocomplete: "Autocomplete"
        case .dictation: "Dictation"
        case .reader: "Reader"
        case .general: "General"
        case .writing: "Writing"
        case .privacy: "Privacy"
        case .developer: "Developer"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .rewrite: "sparkles.rectangle.stack"
        case .autocomplete: "character.cursor.ibeam"
        case .dictation: "mic"
        case .reader: "speaker.wave.2"
        case .general: "gear"
        case .writing: "brain"
        case .privacy: "hand.raised"
        case .developer: "hammer"
        }
    }

    var tint: Color {
        switch self {
        case .overview: .secondary
        case .rewrite: .accentColor
        case .autocomplete: DS.Feature.autocomplete.color
        case .dictation: DS.Feature.dictation.color
        case .reader: DS.Feature.reader.color
        case .general, .writing, .privacy: .secondary
        case .developer: .gray
        }
    }

    init(_ feature: FeatureDefinition.ID) {
        switch feature {
        case .rewrite: self = .rewrite
        case .autocomplete: self = .autocomplete
        case .dictation: self = .dictation
        case .reader: self = .reader
        }
    }
}

/// The one navigation state for the main window, shared so the menu bar
/// extra, the ⌘, command, and in-page settings links can all land the sidebar
/// on a specific page. There is deliberately no separate Settings window —
/// the whole main window is pluma's control panel, and a second surface for
/// "some" settings was the confusion, not the cure.
@MainActor
final class MainNavigation: ObservableObject {
    static let shared = MainNavigation()

    @Published var page: MainPage? = .overview
}

/// One window, one job per page: the sidebar routes between trying Rewrite
/// recipes and the always-on features.
struct MainWindowView: View {
    @EnvironmentObject private var developer: DeveloperMode
    @ObservedObject private var navigation = MainNavigation.shared

    private let featurePages: [MainPage] = [
        .overview, .rewrite, .autocomplete, .dictation, .reader
    ]

    // The Dev page is filtered out rather than disabled: locked, it is not in
    // the view tree at all.
    private var settingsPages: [MainPage] {
        [.general, .writing, .privacy, .developer]
            .filter { $0 != .developer || developer.isUnlocked }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.page) {
                Section {
                    ForEach(featurePages) { page in
                        sidebarRow(page)
                    }
                }
                Section("Settings") {
                    ForEach(settingsPages) { page in
                        sidebarRow(page)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("pluma")
        } detail: {
            switch navigation.page ?? .overview {
            case .overview:
                OverviewView(selection: $navigation.page)
            case .rewrite:
                HomeView()
            case .autocomplete:
                AutocompleteView()
            case .dictation:
                DictationView()
            case .reader:
                ReaderView()
            case .general:
                SettingsPageView(destination: .general)
            case .writing:
                SettingsPageView(destination: .writing)
            case .privacy:
                SettingsPageView(destination: .privacy)
            case .developer:
                DeveloperView()
            }
        }
        .frame(minWidth: 860, minHeight: 620)
        // The cheat-code monitor exists only while the window is open, which
        // for a menu-bar resident app is a small slice of its life.
        .onAppear { developer.startListeningForCheatCode() }
        .onDisappear { developer.stopListeningForCheatCode() }
        .onChange(of: developer.isUnlocked) { _, unlocked in
            if !unlocked, navigation.page == .developer {
                navigation.page = .overview
            }
        }
    }

    private func sidebarRow(_ page: MainPage) -> some View {
        Label {
            Text(page.title)
        } icon: {
            Image(systemName: page.symbolName)
                .foregroundStyle(page.tint)
        }
        .tag(page)
        .accessibilityIdentifier("nav-\(page.rawValue)")
    }
}
