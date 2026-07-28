import Foundation

enum DictationTranscript {
    // Transcriber segments arrive with their own spacing; joining them can
    // leave doubled or trailing whitespace.
    static func assemble(_ raw: String) -> String {
        raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // Cleanup is a round trip through a language model; it isn't worth it for
    // a couple of words, and short fragments are where models hallucinate most.
    static func isWorthCleaningUp(_ text: String) -> Bool {
        text.split(separator: " ").count >= 3
    }

    // Dictating into the middle of a sentence needs a leading space; dictating
    // after a space, a newline, or an opening bracket does not.
    static func insertionText(_ transcript: String, precededBy prefix: String?) -> String {
        let text = assemble(transcript)
        guard !text.isEmpty else { return "" }
        guard let prefix, let last = prefix.last else { return text }

        if last.isWhitespace || last.isNewline { return text }
        if Self.openingCharacters.contains(last) { return text }
        return " " + text
    }

    private static let openingCharacters: Set<Character> = [
        "(", "[", "{", "\"", "'", "“", "‘", "<", "/", "-", "—", "@", "#", "$"
    ]
}
