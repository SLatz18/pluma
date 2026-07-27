import Foundation

enum RewriteProviderChoice: String, CaseIterable, Codable, Identifiable, Sendable {
    case appleIntelligence
    case ollama

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleIntelligence: "Apple Intelligence"
        case .ollama: "Ollama"
        }
    }

    var symbolName: String {
        switch self {
        case .appleIntelligence: "apple.intelligence"
        case .ollama: "desktopcomputer"
        }
    }

    static let defaultProvider: RewriteProviderChoice = .appleIntelligence
}
