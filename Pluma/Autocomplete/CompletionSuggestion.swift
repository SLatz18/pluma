import Foundation

struct CompletionSuggestion: Equatable, Sendable {
    private(set) var remaining: String

    init(rawOutput: String) {
        // Keep leading whitespace: the model uses a leading space to mark a
        // word boundary versus a mid-word continuation, and dropping it fuses
        // words on insertion. Trailing whitespace and extra lines are dropped.
        var text = rawOutput
        if let newlineIndex = text.firstIndex(of: "\n") {
            text = String(text[..<newlineIndex])
        }
        while text.last?.isWhitespace == true {
            text.removeLast()
        }

        guard !Self.looksLikeRefusal(text) else {
            remaining = ""
            return
        }

        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        if words.count > Self.maxWords {
            text = words.prefix(Self.maxWords).joined(separator: " ")
        }
        if text.allSatisfy(\.isWhitespace) {
            text = ""
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

    // Apple's on-device model sometimes answers with a refusal preamble
    // instead of a completion; never render that as a suggestion.
    static func looksLikeRefusal(_ text: String) -> Bool {
        let lowered = text.trimmingCharacters(in: .whitespaces).lowercased()
        let prefixes = ["i'm sorry", "i am sorry", "i apologize", "i cannot", "i can't"]
        return prefixes.contains(where: { lowered.hasPrefix($0) })
            || lowered.contains("as an ai")
            || lowered.contains("as an llm")
    }

    // Returns true while suggestion text remains; false on mismatch or when
    // fully consumed. A leading space on the suggestion is treated as part of
    // the boundary, so typed text may omit it.
    mutating func consumeTypedText(_ typed: String) -> Bool {
        guard !typed.isEmpty else { return true }
        // A typed space at a word boundary consumes the boundary itself; the
        // suggestion (whose leading space the model may have stripped) lives on.
        if typed == " ", !remaining.hasPrefix(" ") {
            return true
        }
        let lowered = remaining.lowercased()
        let typedLower = typed.lowercased()

        if lowered.hasPrefix(typedLower) {
            remaining.removeFirst(typed.count)
        } else if remaining.hasPrefix(" "), !typed.hasPrefix(" "),
                  lowered.hasPrefix(" " + typedLower) {
            remaining.removeFirst(typed.count + 1)
        } else {
            return false
        }
        return !remaining.isEmpty
    }

    // Takes the next word including its surrounding boundary spaces, so
    // inserting pieces one by one reassembles the full suggestion exactly.
    mutating func acceptNextWord() -> String {
        var accepted = ""
        if remaining.hasPrefix(" ") {
            accepted.append(" ")
            remaining.removeFirst()
        }
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
