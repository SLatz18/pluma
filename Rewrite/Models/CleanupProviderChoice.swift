import Foundation

// Which model tidies a dictated transcript. Separate from RewriteProviderChoice
// on purpose: the provider that rewrites a selection is a different decision
// from the one that cleans up speech, and keeping them apart is what lets the
// two be compared against each other on the same utterance.
enum CleanupProviderChoice: String, CaseIterable, Codable, Identifiable, Sendable {
    case appleOnDevice
    case ollama
    case openAI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleOnDevice: "Apple (on device)"
        case .ollama: "Ollama (local)"
        case .openAI: "OpenAI"
        }
    }

    var detail: String {
        switch self {
        case .appleOnDevice: "Private, free, and roughly a 3B model."
        case .ollama: "Private and free, using whichever model you have pulled."
        case .openAI: "Sends the transcript text to OpenAI."
        }
    }

    // Both of these compete for the same local compute, so the comparison has to
    // run them one at a time or they slander each other's timings.
    var isLocal: Bool {
        switch self {
        case .appleOnDevice, .ollama: true
        case .openAI: false
        }
    }

    static let defaultProvider: CleanupProviderChoice = .appleOnDevice
}
