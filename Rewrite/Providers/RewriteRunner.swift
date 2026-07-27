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
}
