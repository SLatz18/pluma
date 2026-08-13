import Foundation

enum OpenAITTSVoice: String, CaseIterable, Codable, Identifiable, Sendable {
    case alloy
    case ash
    case coral
    case echo
    case fable
    case nova
    case onyx
    case sage
    case shimmer

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    static let defaultVoice: OpenAITTSVoice = .nova
}
