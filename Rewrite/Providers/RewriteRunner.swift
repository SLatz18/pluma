import Foundation

enum RewriteRunner {
    static func rewrite(
        provider: RewriteProviderChoice,
        intent: RewriteIntent,
        text: String,
        ollamaModel: String
    ) async throws -> String {
        switch provider {
        case .appleIntelligence:
            try await AppleIntelligenceEngine.rewrite(text, intent: intent)
        case .ollama:
            try await OllamaEngine().rewrite(text, intent: intent, model: ollamaModel)
        }
    }

    static func complete(
        provider: RewriteProviderChoice,
        context: String,
        surrounding: String? = nil,
        ollamaModel: String
    ) async throws -> String {
        switch provider {
        case .appleIntelligence:
            try await AppleIntelligenceEngine.complete(context, surrounding: surrounding)
        case .ollama:
            try await OllamaEngine().complete(context, model: ollamaModel, surrounding: surrounding)
        }
    }
}
