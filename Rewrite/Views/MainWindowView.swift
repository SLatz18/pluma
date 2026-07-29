import SwiftUI

enum MainPage: String, CaseIterable, Identifiable, Hashable {
    case playground
    case autocomplete
    case dictation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playground: "Playground"
        case .autocomplete: "Autocomplete"
        case .dictation: "Dictation"
        }
    }

    var symbolName: String {
        switch self {
        case .playground: "sparkles.rectangle.stack"
        case .autocomplete: "character.cursor.ibeam"
        case .dictation: "mic"
        }
    }

    var tint: Color {
        switch self {
        case .playground: .accentColor
        case .autocomplete: DS.Feature.autocomplete.color
        case .dictation: DS.Feature.dictation.color
        }
    }
}

/// One window, one job per page: the sidebar routes between trying Rewrite
/// (Playground) and the two always-on features. This replaces the single
/// endless scroll that mixed doing and configuring.
struct MainWindowView: View {
    @State private var selection: MainPage? = .playground

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
            .navigationTitle("Rewrite")
        } detail: {
            switch selection ?? .playground {
            case .playground:
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
