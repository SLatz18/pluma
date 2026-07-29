import Foundation

enum OpenAIChatModel: String, CaseIterable, Codable, Identifiable, Sendable {
    case luna = "gpt-5.6-luna"
    case terra = "gpt-5.6-terra"
    case sol = "gpt-5.6-sol"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .luna: "GPT-5.6 Luna"
        case .terra: "GPT-5.6 Terra"
        case .sol: "GPT-5.6 Sol"
        }
    }

    var detail: String {
        switch self {
        case .luna: "Cheapest and fastest. $1 / $6 per million tokens."
        case .terra: "Balanced. $2.50 / $15 per million tokens."
        case .sol: "Flagship. $5 / $30 per million tokens."
        }
    }

    // Tidying a dictated sentence is a mechanical edit sitting in the middle of
    // an interactive keystroke, so the cheap tier with reasoning off is the
    // right default; the others exist to be compared against it.
    static let defaultModel: OpenAIChatModel = .luna
}
