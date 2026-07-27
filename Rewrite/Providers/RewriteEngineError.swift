import Foundation

enum RewriteEngineError: LocalizedError {
    case modelUnavailable(String)
    case providerNotReady(String)
    case providerBusy
    case ollamaUnavailable
    case cloudOllamaModel
    case providerFailure(String)
    case noOllamaModels
    case inputTooLong
    case modelRefused
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
        case .providerBusy:
            "The local model is busy. Wait a moment, then try again."
        case .ollamaUnavailable:
            "Rewrite could not connect to Ollama at 127.0.0.1:11434."
        case .cloudOllamaModel:
            "Choose an Ollama model stored on this Mac. Cloud models are not supported."
        case .providerFailure(let reason):
            reason
        case .noOllamaModels:
            "Ollama is running, but no local models are installed."
        case .inputTooLong:
            "This text is too long for Apple Intelligence. Try a shorter selection."
        case .modelRefused:
            "The local model declined the rewrite, so the original text was left unchanged."
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
