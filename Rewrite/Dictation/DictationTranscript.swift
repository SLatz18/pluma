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

    // Under three words is a name, a command, or an answer — not prose.
    static func isFragment(_ text: String) -> Bool {
        text.split(separator: " ").count < 3
    }

    // Cleanup is a round trip through a language model; it isn't worth it for
    // a couple of words, and short fragments are where models hallucinate most.
    static func isWorthCleaningUp(_ text: String) -> Bool {
        !isFragment(text)
    }

    // SpeechTranscriber has no way to turn punctuation off, and it closes every
    // utterance with a period, so dictating a single name yields "Alex." A
    // question or exclamation mark reflects how the speaker actually said it,
    // and an ellipsis is deliberate, so only a lone final period is dropped.
    static func withoutFragmentPeriod(_ text: String) -> String {
        guard isFragment(text), text.hasSuffix("."), !text.hasSuffix("..") else { return text }
        return String(text.dropLast())
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
