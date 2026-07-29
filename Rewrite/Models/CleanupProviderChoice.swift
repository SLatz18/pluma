import Foundation

// Which model tidies a dictated transcript. Separate from RewriteProviderChoice
// on purpose: the provider that rewrites a selection is a different decision
// from the one that cleans up speech, and keeping them apart is what lets the
// two be compared against each other on the same utterance.
enum CleanupProviderChoice: String, CaseIterable, Codable, Identifiable, Sendable {
    case appleOnDevice
    case openAI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleOnDevice: "Apple (on device)"
        case .openAI: "OpenAI"
        }
    }

    var detail: String {
        switch self {
        case .appleOnDevice: "Private, free, and roughly a 3B model."
        case .openAI: "Sends the transcript text to OpenAI."
        }
    }

    static let defaultProvider: CleanupProviderChoice = .appleOnDevice
}
