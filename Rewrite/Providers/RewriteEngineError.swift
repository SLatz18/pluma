import Foundation

enum RewriteEngineError: LocalizedError {
    case modelUnavailable(String)
    case providerNotReady(String)
    case ollamaUnavailable
    case providerFailure(String)
    case noOllamaModels
    case invalidResponse
    case serviceTimedOut
    case emptySelection
    case emptyChain

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason):
            reason
        case .providerNotReady(let reason):
            reason
        case .ollamaUnavailable:
            "Rewrite could not connect to Ollama at 127.0.0.1:11434."
        case .providerFailure(let reason):
            reason
        case .noOllamaModels:
            "Ollama is running, but no local models are installed."
        case .invalidResponse:
            "The local model returned an unreadable response."
        case .serviceTimedOut:
            "The rewrite took too long. Please try again."
        case .emptySelection:
            "Select some editable text first."
        case .emptyChain:
            "Pick at least one recipe on the Rewrite page."
        }
    }
}
