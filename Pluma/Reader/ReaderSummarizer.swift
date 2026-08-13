import Foundation

enum ReaderDeliveryMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case verbatim
    case summarizeWhenHelpful

    var id: String { rawValue }

    var title: String {
        switch self {
        case .verbatim: "Read verbatim"
        case .summarizeWhenHelpful: "Summarize, then read"
        }
    }

    var shortTitle: String {
        switch self {
        case .verbatim: "Read"
        case .summarizeWhenHelpful: "Summarize & Read"
        }
    }

    var shortDescription: String {
        switch self {
        case .verbatim: "Keep every word exactly as written"
        case .summarizeWhenHelpful: "Condense long text; preserve key details"
        }
    }

    var symbolName: String {
        switch self {
        case .verbatim: "text.quote"
        case .summarizeWhenHelpful: "text.alignleft"
        }
    }
}

@MainActor
protocol ReaderSummarizing {
    func summarize(_ text: String) async throws -> String
}

@MainActor
struct ConfiguredReaderSummarizer: ReaderSummarizing {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func summarize(_ text: String) async throws -> String {
        let output = try await RewriteRunner.rewrite(
            provider: Preferences.provider(from: defaults),
            directive: PromptComposer.readerSummaryDirective,
            text: text,
            ollamaModel: Preferences.ollamaModel(from: defaults)
        )
        return try RewriteRunner.validatedOutput(output)
    }
}
