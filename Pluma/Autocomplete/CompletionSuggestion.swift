import Foundation

// How much continuation is worth drawing. Length is not free: every word of
// ghost text is a word the writer has to read and judge before carrying on, so a
// long guess made from thin context costs more than it offers. When the sentence
// has not declared its direction yet, one word is the honest suggestion.
// The numbers that decide how much a suggestion says and how eagerly it asks.
// Gathered into one value because they are only ever tuned against each other —
// a longer suggestion wants a longer pause behind it — and because guessing them
// from the outside was costing a rebuild per guess. Exposed on the Developer
// page; `standard` is what ships.
struct CompletionTuning: Equatable, Sendable {
    var phraseWords: Int
    var briefWords: Int
    var debounceMilliseconds: Int
    var minimumContext: Int

    static let standard = CompletionTuning(
        phraseWords: 14,
        briefWords: 4,
        debounceMilliseconds: 650,
        minimumContext: 16
    )

    static let phraseWordRange = 1...25
    static let briefWordRange = 1...12
    static let debounceRange = 150...1_500
    static let minimumContextRange = 4...80

    // Anything read back from defaults is clamped: a zero word limit or a zero
    // debounce would look like the feature was broken rather than mistuned.
    func clamped() -> CompletionTuning {
        CompletionTuning(
            phraseWords: Self.phraseWordRange.clamping(phraseWords),
            briefWords: Self.briefWordRange.clamping(briefWords),
            debounceMilliseconds: Self.debounceRange.clamping(debounceMilliseconds),
            minimumContext: Self.minimumContextRange.clamping(minimumContext)
        )
    }
}

extension ClosedRange where Bound == Int {
    func clamping(_ value: Int) -> Int { Swift.min(upperBound, Swift.max(lowerBound, value)) }
}

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

    func wordLimit(_ tuning: CompletionTuning = .standard) -> Int {
        switch self {
        case .word: 1
        case .brief: tuning.briefWords
        case .phrase: tuning.phraseWords
        }
    }
}

struct CompletionSuggestion: Equatable, Sendable {
    private(set) var remaining: String

    init(
        rawOutput: String,
        context: String = "",
        scope: CompletionScope = .phrase,
        tuning: CompletionTuning = .standard
    ) {
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

        text = Self.limitingWords(text, to: scope.wordLimit(tuning))

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

        // The model sometimes restates a run of words it has *not* finished —
        // given "…a test of the functionality" it offers "of the functionali".
        // That is redundant however it ends, so the whole thing goes.
        if isContainedInTail(body, tail: tail) { return "" }

        // …and sometimes it lands back where the writer already is, closing with
        // the very words the caret sits after. Whatever it did in between, a
        // suggestion that ends by retyping the end of the line is not a
        // continuation.
        if endsWithContextTail(body, tail: tail) { return "" }

        guard let echo = longestEchoedTail(of: tail, openingOf: body) else { return suggestion }

        var stripped = String(body.dropFirst(echo.length))
        // The context still ends mid-sentence, so whatever survives has to
        // rejoin it across a word boundary.
        while stripped.first?.isWhitespace == true {
            stripped.removeFirst()
        }
        // What is left of a restated line is often just the punctuation the model
        // tacked on, or a single stray letter. Neither is worth interrupting the
        // writer for, and both are what a mostly-echoed answer leaves behind.
        guard stripped.filter(\.isLetterOrDigit).count >= minimumEchoLength else { return "" }

        // Restore the word boundary the comparison skipped — but only for a
        // word. Punctuation belongs tight against the writer's last word, so
        // " . Let me know" would be wrong where ". Let me know" is right. And a
        // strip that ended inside a word is finishing that word, so "work" +
        // "ing on." must not become "work ing on."
        guard
            !echo.endedMidWord,
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
    private struct Echo {
        let length: Int
        // True when the repeated run stopped inside a word of the suggestion,
        // which means what follows finishes that word rather than starting one.
        let endedMidWord: Bool
    }

    private static func longestEchoedTail(of context: String, openingOf body: String) -> Echo? {
        let contextLower = context.lowercased()
        let bodyLower = body.lowercased()

        for start in wordStarts(in: contextLower).sorted() {
            // Trailing whitespace on the context is the writer's word boundary,
            // not part of the repeated words. Leaving it on made every candidate
            // one character longer than the echo it was meant to match, which
            // defeated the whole check the moment the caret sat after a space.
            let candidate = String(
                contextLower[start...].reversed().drop(while: \.isWhitespace).reversed()
            )
            guard candidate.count >= minimumEchoLength, candidate.count <= bodyLower.count else {
                continue
            }
            guard bodyLower.hasPrefix(candidate) else { continue }
            let next = bodyLower.index(bodyLower.startIndex, offsetBy: candidate.count)
            // Punctuation ends a word as surely as a space does: the model likes
            // to repeat the line and add the full stop the writer had not typed
            // yet, and that trailing "." must not disguise the echo.
            if next == bodyLower.endIndex || !bodyLower[next].isLetterOrDigit {
                return Echo(length: candidate.count, endedMidWord: false)
            }
            // The match ran into the middle of a longer word. That is fine when
            // several words matched — "I am work" against "I am working on" is
            // the model restating the line and finishing the last word, and the
            // continuation the writer wants is "ing on". It is not fine for a
            // single word, where "apple" against "applesauce" is just two words
            // that start alike.
            if candidate.split(separator: " ").count >= minimumEchoWords {
                return Echo(length: candidate.count, endedMidWord: true)
            }
        }
        return nil
    }

    // True when the suggestion is just words the writer already has — the model
    // re-typing the tail of the context instead of extending it, whether or not
    // it got to the end of the last word.
    private static func isContainedInTail(_ body: String, tail: String) -> Bool {
        let bodyLower = body.lowercased()
        guard bodyLower.count >= minimumEchoLength else { return false }
        let tailLower = tail.lowercased()

        for start in wordStarts(in: tailLower).sorted() {
            let candidate = String(tailLower[start...])
            guard candidate.count >= bodyLower.count else { continue }
            if candidate.hasPrefix(bodyLower) { return true }
        }
        return false
    }

    // True when the suggestion finishes on the same run of words the context
    // finishes on. Two words is enough to mean it: a genuine continuation lands
    // somewhere new, and one shared word is ordinary English.
    private static func endsWithContextTail(_ body: String, tail: String) -> Bool {
        let bodyWords = body.lowercased().split(separator: " ").map(String.init)
        let tailWords = tail.lowercased().split(separator: " ").map(String.init)
        guard bodyWords.count >= 2, tailWords.count >= 2 else { return false }

        for count in stride(from: min(4, min(bodyWords.count, tailWords.count)), through: 2, by: -1)
        where Array(bodyWords.suffix(count)) == Array(tailWords.suffix(count)) {
            return true
        }
        return false
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

    // How many repeated words it takes before a match is allowed to end inside a
    // word. Two is enough to be deliberate rather than coincidence.
    static let minimumEchoWords = 2

    // A full-line echo is the failure worth catching; anything longer than a
    // sentence or two of context cannot be one, and scanning it is wasted work.
    static let maxEchoLength = 400

    var isEmpty: Bool { remaining.isEmpty }

    static let maxWords = 14

    static let minimumContextLength = 16

    static func shouldTrigger(
        for prefix: String, tuning: CompletionTuning = .standard
    ) -> Bool {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= tuning.minimumContext
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
