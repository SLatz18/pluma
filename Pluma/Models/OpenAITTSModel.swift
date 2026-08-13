import Foundation

enum OpenAITTSModel: String, CaseIterable, Codable, Identifiable, Sendable {
    case tts1 = "tts-1"
    case tts1HD = "tts-1-hd"
    case gpt4oMiniTTS = "gpt-4o-mini-tts"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tts1: "TTS-1"
        case .tts1HD: "TTS-1 HD"
        case .gpt4oMiniTTS: "GPT-4o mini TTS"
        }
    }

    var detail: String {
        switch self {
        case .tts1: "Fastest and cheapest."
        case .tts1HD: "Higher fidelity system voice."
        case .gpt4oMiniTTS: "Newest OpenAI speech model."
        }
    }

    static let defaultModel: OpenAITTSModel = .tts1HD
}
