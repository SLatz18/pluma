import Foundation

/// Where Reader turns text into audio. Separate from the writing provider so
/// summarize-then-read can stay on-device while speech uses OpenAI (or the reverse).
enum ReaderSpeechProviderChoice: String, CaseIterable, Codable, Identifiable, Sendable {
    case appleOnDevice
    case openAI
    case customOpenAICompatible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleOnDevice: "Apple (on device)"
        case .openAI: "OpenAI"
        case .customOpenAICompatible: "Custom endpoint"
        }
    }

    var detail: String {
        switch self {
        case .appleOnDevice: "System voices. Premium downloads stay on this Mac."
        case .openAI: "Sends the text to OpenAI for speech."
        case .customOpenAICompatible: "Sends the text to an OpenAI-compatible endpoint you configure."
        }
    }

    var symbolName: String {
        switch self {
        case .appleOnDevice: "laptopcomputer"
        case .openAI: "cloud"
        case .customOpenAICompatible: "server.rack"
        }
    }

    var isLocal: Bool {
        switch self {
        case .appleOnDevice: true
        case .openAI: false
        case .customOpenAICompatible: false
        }
    }

    static let defaultProvider: ReaderSpeechProviderChoice = .appleOnDevice
}
