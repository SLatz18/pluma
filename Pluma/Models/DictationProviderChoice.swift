import Foundation

enum DictationProviderChoice: String, CaseIterable, Codable, Identifiable, Sendable {
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
        case .appleOnDevice: "Private. Nothing leaves your Mac."
        case .openAI: "Sends microphone audio to OpenAI."
        }
    }

    static let defaultProvider: DictationProviderChoice = .appleOnDevice
}
