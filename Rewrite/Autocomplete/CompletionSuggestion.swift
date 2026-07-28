import Foundation

struct CompletionSuggestion: Equatable, Sendable {
    private(set) var remaining: String

    init(rawOutput: String) {
        var text = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if let newlineIndex = text.firstIndex(of: "\n") {
            text = String(text[..<newlineIndex])
        }
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        if words.count > Self.maxWords {
            text = words.prefix(Self.maxWords).joined(separator: " ")
        }
        remaining = text
    }

    var isEmpty: Bool { remaining.isEmpty }

    static let maxWords = 14

    static let minimumContextLength = 16

    static func shouldTrigger(for prefix: String) -> Bool {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= minimumContextLength
    }

    mutating func consumeTypedText(_ typed: String) -> Bool {
        guard !typed.isEmpty else { return true }
        if remaining.lowercased().hasPrefix(typed.lowercased()) {
            remaining.removeFirst(typed.count)
            if remaining.hasPrefix(" ") {
                remaining.removeFirst()
            }
            return !remaining.isEmpty
        }
        return false
    }

    mutating func acceptNextWord() -> String {
        var accepted = ""
        while let first = remaining.first, !first.isWhitespace {
            accepted.append(first)
            remaining.removeFirst()
        }
        if remaining.hasPrefix(" ") {
            accepted.append(" ")
            remaining.removeFirst()
        }
        return accepted
    }

    mutating func acceptAll() -> String {
        let accepted = remaining
        remaining = ""
        return accepted
    }
}
