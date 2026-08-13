import SwiftUI

enum MainPage: String, CaseIterable, Identifiable, Hashable {
    case overview
    case rewrite
    case autocomplete
    case dictation
    case reader
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

/// One window, one job per page: the sidebar routes between trying Rewrite
/// recipes and the always-on features.
struct MainWindowView: View {
    @EnvironmentObject private var developer: DeveloperMode
    @State private var selection: MainPage? = .overview

    // The Dev page is filtered out rather than disabled: locked, it is not in
    // the view tree at all.
    private var pages: [MainPage] {
        MainPage.allCases.filter { $0 != .developer || developer.isUnlocked }
    }

    var body: some View {
        NavigationSplitView {
            List(pages, selection: $selection) { page in
                Label {
                    Text(page.title)
                } icon: {
                    Image(systemName: page.symbolName)
                        .foregroundStyle(page.tint)
                }
                .tag(page)
                .accessibilityIdentifier("nav-\(page.rawValue)")
            }
            .listStyle(.sidebar)
            .navigationTitle("pluma")
        } detail: {
            switch selection ?? .overview {
            case .overview:
                OverviewView(selection: $selection)
            case .rewrite:
                HomeView()
            case .autocomplete:
                AutocompleteView()
            case .dictation:
                DictationView()
            case .reader:
                ReaderView()
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
            if !unlocked, selection == .developer {
                selection = .overview
            }
        }
    }
}
