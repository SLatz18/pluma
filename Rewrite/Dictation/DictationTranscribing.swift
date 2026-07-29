import Foundation

enum TranscriptionAvailability: Equatable {
    case checking
    case preparing
    case ready
    case unsupported(String)
}

// Both backends look the same to the controller: get ready, stream audio while
// the key is held, hand back what was said. Screen-context terms arrive as a
// closure rather than a value because gathering them runs while the microphone
// is already coming up, and each backend feeds them to a different biasing
// mechanism — Apple's contextual strings, or OpenAI's keywords.
@MainActor
protocol DictationTranscribing: AnyObject {
    var availability: TranscriptionAvailability { get }
    var onAvailabilityChange: ((TranscriptionAvailability) -> Void)? { get set }
    var onVolatileText: ((String) -> Void)? { get set }

    func prepare() async
    func start(contextStrings: @Sendable () async -> [String]) async throws
    func finish() async -> String
    func cancel() async
}
