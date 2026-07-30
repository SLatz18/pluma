import Foundation

// How much continuation is worth drawing. Length is not free: every word of
// ghost text is a word the writer has to read and judge before carrying on, so a
// long guess made from thin context costs more than it offers. When the sentence
// has not declared its direction yet, one word is the honest suggestion.
enum CompletionScope: Equatable, Sendable {
    // The writer is partway through a word. Finish that word and stop — where
    // the sentence goes next is a separate guess, and not one worth making
    // while they are still typing this word.
    case word
    // Barely past the trigger threshold. There is not enough here to commit to a
    // clause, so offer a few words the writer can accept or type past.
    case brief
    // Enough context that continuing the thought is a reasonable bet.
    case phrase

    var wordLimit: Int {
        switch self {
        case .word: 1
        case .brief: 4
        case .phrase: CompletionSuggestion.maxWords
        }
    }
}

struct CompletionSuggestion: Equatable, Sendable {
    private(set) var remaining: String

    init(rawOutput: String, context: String = "", scope: CompletionScope = .phrase) {
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

        guard !Self.looksLikeRefusal(text), !Self.leaksPromptMarkup(text) else {
            remaining = ""
            return
        }

        text = Self.strippingEcho(of: context, from: text)

        text = Self.limitingWords(text, to: scope.wordLimit)

        if text.allSatisfy(\.isWhitespace) {
            text = ""
        }
        remaining = text
    }

    // Caps the suggestion without disturbing its leading space, which is the
    // word-boundary marker rather than a word of its own — splitting naively
    // counts it as an empty first word and a one-word limit then yields nothing.
    static func limitingWords(_ text: String, to limit: Int) -> String {
        let leading = text.hasPrefix(" ") ? " " : ""
        let body = leading.isEmpty ? text : String(text.dropFirst())
        let words = body.split(separator: " ", omittingEmptySubsequences: false)
        guard words.count > limit else { return text }
        return leading + words.prefix(limit).joined(separator: " ")
    }

    // Mid-word, the suggestion has to finish the word actually being typed, and
    // the model does not reliably do that: asked to continue "documenta" it
    // offers "documents.", which appends into nonsense. So its answer is taken
    // only when it genuinely extends the partial word into a real one, and the
    // spell checker's own completions stand in when it does not.
    //
    // `candidates` are whole words; the return is only the part still missing.
    static func wordCompletion(
        forPartial partial: String,
        modelSuggestion: String,
        candidates: [String]
    ) -> String {
        guard !partial.isEmpty else { return "" }
        let lowered = partial.lowercased()
        let extending = candidates.filter {
            $0.count > partial.count && $0.lowercased().hasPrefix(lowered)
        }

        let proposed = limitingWords(modelSuggestion, to: 1)
            .trimmingCharacters(in: .whitespaces)
        if !proposed.isEmpty, extending.contains(where: {
            $0.lowercased() == lowered + proposed.lowercased()
        }) {
            return proposed
        }

        guard let best = extending.first else { return "" }
        return String(best.dropFirst(partial.count))
    }

    // Mid-word is decided by the caller, which has the spell checker; everything
    // else follows from how much the writer has committed to so far.
    static func scope(forContext context: String, endsMidWord: Bool) -> CompletionScope {
        if endsMidWord { return .word }
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count < briefContextLength ? .brief : .phrase
    }

    // Below roughly a short sentence, any clause the model produces is invention
    // rather than continuation.
    static let briefContextLength = 60

    // The on-device model restates what the writer just typed instead of
    // continuing it — sometimes the last word, sometimes the whole line — and
    // the instruction not to is not enough to stop it. So the overlap is cut
    // here: the longest whole-word tail of the context that the suggestion
    // opens with is dropped, which turns "the middle section" +
    // " section is important" into " is important", and a verbatim echo of the
    // whole line into nothing at all.
    static func strippingEcho(of context: String, from suggestion: String) -> String {
        guard !context.isEmpty, !suggestion.isEmpty else { return suggestion }

        // A leading space is the model's word-boundary marker, not part of the
        // repeated words, so comparison skips it and the boundary is restored
        // afterwards from the context.
        let body = suggestion.hasPrefix(" ") ? String(suggestion.dropFirst()) : suggestion
        guard !body.isEmpty else { return suggestion }

        let tail = String(context.suffix(maxEchoLength))
        guard let overlap = longestEchoedTail(of: tail, openingOf: body) else { return suggestion }

        var stripped = String(body.dropFirst(overlap))
        // The context still ends mid-sentence, so whatever survives has to
        // rejoin it across a word boundary.
        while stripped.first?.isWhitespace == true {
            stripped.removeFirst()
        }
        // What is left of a restated line is often just the punctuation the
        // model tacked on. A lone "." is not a suggestion worth drawing.
        guard stripped.contains(where: \.isLetterOrDigit) else { return "" }

        // Restore the word boundary the comparison skipped — but only for a
        // word. Punctuation belongs tight against the writer's last word, so
        // " . Let me know" would be wrong where ". Let me know" is right.
        guard
            context.last?.isWhitespace == false,
            stripped.first?.isLetterOrDigit == true
        else { return stripped }
        return " " + stripped
    }

    // Whole-word tails only, longest first, and the match has to end on a word
    // boundary in the suggestion as well as begin on one in the context. Both
    // halves of that matter: without the first, "…the mid" would cut into a
    // suggestion of "midpoint"; without the second, it still would, leaving the
    // writer "the point".
    private static func longestEchoedTail(of context: String, openingOf body: String) -> Int? {
        let contextLower = context.lowercased()
        let bodyLower = body.lowercased()

        for start in wordStarts(in: contextLower).sorted() {
            let candidate = String(contextLower[start...])
            guard candidate.count >= minimumEchoLength, candidate.count <= bodyLower.count else {
                continue
            }
            guard bodyLower.hasPrefix(candidate) else { continue }
            let next = bodyLower.index(bodyLower.startIndex, offsetBy: candidate.count)
            // Punctuation ends a word as surely as a space does: the model likes
            // to repeat the line and add the full stop the writer had not typed
            // yet, and that trailing "." must not disguise the echo. Only a
            // letter or digit means the match ran into the middle of a longer
            // word and has to be refused.
            if next == bodyLower.endIndex || !bodyLower[next].isLetterOrDigit {
                return candidate.count
            }
        }
        return nil
    }

    // Indices that begin a word: the string's own start, plus every position
    // following whitespace. Sorted ascending, so the earliest — and therefore
    // the longest candidate tail — is tried first.
    private static func wordStarts(in text: String) -> [String.Index] {
        var starts: [String.Index] = []
        var index = text.startIndex
        var previousWasSpace = true
        while index < text.endIndex {
            if previousWasSpace, !text[index].isWhitespace {
                starts.append(index)
            }
            previousWasSpace = text[index].isWhitespace
            index = text.index(after: index)
        }
        return starts
    }

    // Two characters, because a single repeated letter is as likely to be the
    // writer's own ("option A" continuing "A is cheaper") as it is an echo.
    static let minimumEchoLength = 2

    // A full-line echo is the failure worth catching; anything longer than a
    // sentence or two of context cannot be one, and scanning it is wasted work.
    static let maxEchoLength = 400

    var isEmpty: Bool { remaining.isEmpty }

    static let maxWords = 14

    static let minimumContextLength = 16

    static func shouldTrigger(for prefix: String) -> Bool {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= minimumContextLength
    }

    // The context handed to the model is fenced in <context> markers, and the
    // model sometimes continues the *prompt* rather than the writer — closing the
    // tag instead of finishing the sentence. Seen live as a suggestion of exactly
    // "</context>". Any output carrying one of our own markers is the model
    // talking about the prompt, so none of it is a completion.
    static func leaksPromptMarkup(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return promptMarkers.contains { lowered.contains($0) }
    }

    private static let promptMarkers = [
        "<context", "</context", "<surrounding", "</surrounding",
        "<style-profile", "</style-profile", "<memory", "</memory"
    ]

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

private extension Character {
    // Word-continuing characters, as opposed to the spaces and punctuation that
    // end a word.
    var isLetterOrDigit: Bool { isLetter || isNumber }
}
