import SwiftUI

enum MainPage: String, CaseIterable, Identifiable, Hashable {
    case overview
    case rewrite
    case autocomplete
    case dictation
    case reader
    case general
    case ai
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
        case .ai: "AI"
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
        case .ai: "sparkles"
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
        case .general, .ai, .writing, .privacy: .secondary
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

enum NavigationFocus: String, Hashable, Sendable {
    case aiOpenAIKey = "ai-openai-access"
    case aiWriting = "ai-writing-settings"
    case aiDictation = "ai-dictation-settings"
    case aiReader = "ai-reader-settings"
    case rewriteModel = "rewrite-model-controls"
    case dictationEngines = "dictation-engine-controls"
    case readerRecipe = "reader-recipe-controls"
    case readerSpeech = "reader-speech-controls"

    var page: MainPage {
        switch self {
        case .aiOpenAIKey, .aiWriting, .aiDictation, .aiReader: .ai
        case .rewriteModel: .rewrite
        case .dictationEngines: .dictation
        case .readerRecipe, .readerSpeech: .reader
        }
    }

    var scrollTarget: String { rawValue }
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
    @Published private(set) var focus: NavigationFocus?

    private struct ReturnRoute {
        let page: MainPage
        let focus: NavigationFocus?
    }

    private var returnRoute: ReturnRoute?
    private var contextualTarget: MainPage?

    func select(_ newPage: MainPage?) {
        page = newPage ?? .overview
        focus = nil
        returnRoute = nil
        contextualTarget = nil
    }

    func navigate(
        to target: MainPage,
        focus: NavigationFocus? = nil,
        returningTo returnPage: MainPage? = nil,
        returnFocus: NavigationFocus? = nil
    ) {
        self.focus = focus
        if let returnPage {
            returnRoute = ReturnRoute(page: returnPage, focus: returnFocus)
            contextualTarget = target
        } else {
            returnRoute = nil
            contextualTarget = nil
        }
        page = target
    }

    func canReturn(from page: MainPage) -> Bool {
        contextualTarget == page && returnRoute != nil
    }

    func returnPage(from page: MainPage) -> MainPage? {
        guard contextualTarget == page else { return nil }
        return returnRoute?.page
    }

    func goBack(from page: MainPage) {
        guard contextualTarget == page, let route = returnRoute else { return }
        returnRoute = nil
        contextualTarget = nil
        focus = route.focus
        self.page = route.page
    }
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
        [.general, .ai, .writing, .privacy, .developer]
            .filter { $0 != .developer || developer.isUnlocked }
    }

    private var pageSelection: Binding<MainPage?> {
        Binding(
            get: { navigation.page },
            set: { navigation.select($0) }
        )
    }

    private var currentPage: MainPage {
        navigation.page ?? .overview
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: pageSelection) {
                    Section {
                        ForEach(featurePages) { page in
                            sidebarRow(page)
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(maxHeight: .infinity, alignment: .top)

                settingsFooter
            }
            .navigationTitle("pluma")
        } detail: {
            detailContent
                .navigationTitle(currentPage.title)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
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

    /// Settings stay glued to the bottom of the sidebar, Safari/Finder-style.
    /// Deliberately background-free so the sidebar's own material runs
    /// unbroken from the feature list down through this block. Rows call
    /// `MainNavigation` directly so selection stays reliable outside the
    /// feature List (a second `List` with the same binding was flaky).
    private var settingsFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 2)

            ForEach(settingsPages) { page in
                settingsFooterRow(page)
            }
        }
        .padding(.top, DS.Spacing.small)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsFooterRow(_ page: MainPage) -> some View {
        let isSelected = currentPage == page
        return Button {
            navigation.select(page)
        } label: {
            Label {
                Text(page.title)
            } icon: {
                Image(systemName: page.symbolName)
                    .foregroundStyle(isSelected ? Color.white : page.tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: DS.Radius.badge, style: .continuous)
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .accessibilityIdentifier("nav-\(page.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var detailContent: some View {
        switch currentPage {
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
        case .ai:
            SettingsPageView(destination: .ai)
        case .writing:
            SettingsPageView(destination: .writing)
        case .privacy:
            SettingsPageView(destination: .privacy)
        case .developer:
            DeveloperView()
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
