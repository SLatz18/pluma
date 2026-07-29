import SwiftUI

enum MainPage: String, CaseIterable, Identifiable, Hashable {
    case rewrite
    case autocomplete
    case dictation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rewrite: "Rewrite"
        case .autocomplete: "Autocomplete"
        case .dictation: "Dictation"
        }
    }

    var symbolName: String {
        switch self {
        case .rewrite: "sparkles.rectangle.stack"
        case .autocomplete: "character.cursor.ibeam"
        case .dictation: "mic"
        }
    }

    var tint: Color {
        switch self {
        case .rewrite: .accentColor
        case .autocomplete: DS.Feature.autocomplete.color
        case .dictation: DS.Feature.dictation.color
        }
    }
}

/// One window, one job per page: the sidebar routes between trying Rewrite
/// recipes (the home page) and the two always-on features.
struct MainWindowView: View {
    @State private var selection: MainPage? = .rewrite

    var body: some View {
        NavigationSplitView {
            List(MainPage.allCases, selection: $selection) { page in
                Label {
                    Text(page.title)
                } icon: {
                    Image(systemName: page.symbolName)
                        .foregroundStyle(page.tint)
                }
                .tag(page)
            }
            .listStyle(.sidebar)
            .navigationTitle("pluma")
        } detail: {
            switch selection ?? .rewrite {
            case .rewrite:
                HomeView()
            case .autocomplete:
                AutocompleteView()
            case .dictation:
                DictationView()
            }
        }
        .frame(minWidth: 860, minHeight: 620)
    }
}
