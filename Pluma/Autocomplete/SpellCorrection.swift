import Foundation

// A misspelling immediately before the caret, plus the replacement to put in
// its place. Absolute UTF-16 locations match Accessibility selection ranges.
struct SpellCorrectionOffer: Equatable, Sendable {
    let misspelled: String
    let replacement: String
    let wordLocation: Int
    let wordLength: Int
}

enum SpellCorrectionEngine: String, CaseIterable, Sendable {
    case dictionary
    case appleIntelligence
}

enum SpellCorrection {
    // The caret sits after whitespace or punctuation that closed a word. The
    // alphabetic run before that boundary is the finished word — "teh " and
    // "teh." both yield "teh"; a caret still inside the word yields nothing.
    static func finishedWordRange(inPrefix prefix: String) -> (word: String, range: NSRange)? {
        guard let last = prefix.last, !last.isLetter else { return nil }
        return letterRun(endingBefore: trailingNonLettersStart(in: prefix), in: prefix)
    }

    // Trailing alphabetic token whether or not the word is finished — used when
    // Apple Intelligence should fix mid-word garble like "adminipera".
    static func trailingWordRange(inPrefix prefix: String) -> (word: String, range: NSRange)? {
        if let finished = finishedWordRange(inPrefix: prefix) {
            return finished
        }
        guard let last = prefix.last, last.isLetter else { return nil }
        return letterRun(endingBefore: prefix.endIndex, in: prefix)
    }

    // Dictionary path: finished misspellings only. Model path: any trailing
    // token the checker does not already accept as a real word.
    static func candidateWordRange(
        inPrefix prefix: String,
        allowMidWord: Bool,
        isMisspelled: (String) -> Bool
    ) -> (word: String, range: NSRange)? {
        let found = allowMidWord
            ? trailingWordRange(inPrefix: prefix)
            : finishedWordRange(inPrefix: prefix)
        guard let (word, range) = found, isMisspelled(word) else { return nil }
        return (word, range)
    }

    // Pure assembly so tests can inject misspell / guess answers without
    // standing up NSSpellChecker. The word range in the prefix is already
    // absolute in the field: text-before-caret starts at location 0.
    static func offer(
        prefix: String,
        isMisspelled: (String) -> Bool,
        guessesFor: (String) -> [String]
    ) -> SpellCorrectionOffer? {
        guard let (word, range) = candidateWordRange(
            inPrefix: prefix, allowMidWord: false, isMisspelled: isMisspelled
        ) else { return nil }
        guard
            let replacement = guessesFor(word).first,
            let offer = offer(misspelled: word, range: range, replacement: replacement)
        else { return nil }
        return offer
    }

    static func offer(
        misspelled: String,
        range: NSRange,
        replacement: String
    ) -> SpellCorrectionOffer? {
        let cleaned = sanitizedModelReplacement(replacement, forMisspelling: misspelled)
        guard !cleaned.isEmpty else { return nil }
        return SpellCorrectionOffer(
            misspelled: misspelled,
            replacement: cleaned,
            wordLocation: range.location,
            wordLength: range.length
        )
    }

    // Text before the candidate token, so the model can use prior words without
    // seeing the broken token twice.
    static func precedingText(inPrefix prefix: String, wordRange: NSRange) -> String {
        let ns = prefix as NSString
        guard wordRange.location >= 0, wordRange.location <= ns.length else { return "" }
        return ns.substring(to: wordRange.location)
    }

    // Models sometimes wrap the answer in quotes or tack on a second word.
    // Spelling replace must stay a single token that actually changes the text,
    // and must look like a fix of the token — not a copy of an earlier word.
    static func sanitizedModelReplacement(
        _ raw: String,
        forMisspelling misspelled: String,
        preceding: String = ""
    ) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let newline = text.firstIndex(of: "\n") {
            text = String(text[..<newline])
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”‘’"))
        if let space = text.firstIndex(where: { $0.isWhitespace }) {
            text = String(text[..<space])
        }
        text = text.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        guard !text.isEmpty, text.caseInsensitiveCompare(misspelled) != .orderedSame else {
            return ""
        }
        guard looksLikeSpellingOf(misspelled, replacement: text) else { return "" }
        // "She will carefully sepera" must not accept "separation".
        if precedingLikelyNeedsVerb(preceding), looksLikeNominalization(text) {
            return ""
        }
        return text
    }

    // Short typos (teh → the) need latitude. Longer partials must share a
    // prefix with the answer so "separ" cannot become "church".
    static func looksLikeSpellingOf(_ misspelled: String, replacement: String) -> Bool {
        let broken = misspelled.lowercased()
        let fixed = replacement.lowercased()
        guard !broken.isEmpty, !fixed.isEmpty else { return false }
        if broken.count <= 4 { return true }
        let shared = min(3, broken.count, fixed.count)
        return broken.prefix(shared) == fixed.prefix(shared)
    }

    // Modal / infinitive marker, optionally followed by one adverb, then the
    // caret — the next word should be a verb ("will carefully ▁", "to ▁").
    static func precedingLikelyNeedsVerb(_ preceding: String) -> Bool {
        let trimmed = preceding
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !trimmed.isEmpty else { return false }
        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
        guard let last = tokens.last else { return false }
        let modals: Set<String> = [
            "will", "would", "can", "could", "should", "must", "may", "might", "shall", "to"
        ]
        if modals.contains(last) { return true }
        guard tokens.count >= 2, last.hasSuffix("ly") else { return false }
        return modals.contains(tokens[tokens.count - 2])
    }

    static func looksLikeNominalization(_ word: String) -> Bool {
        let lower = word.lowercased()
        let suffixes = ["tion", "sion", "ment", "ance", "ence", "ness", "ity"]
        return suffixes.contains { lower.hasSuffix($0) }
    }

    static func fitsGrammatically(_ replacement: String, after preceding: String) -> Bool {
        !(precedingLikelyNeedsVerb(preceding) && looksLikeNominalization(replacement))
    }

    private static func trailingNonLettersStart(in prefix: String) -> String.Index {
        var index = prefix.endIndex
        while index > prefix.startIndex {
            let previous = prefix.index(before: index)
            if prefix[previous].isLetter { break }
            index = previous
        }
        return index
    }

    private static func letterRun(
        endingBefore wordEnd: String.Index,
        in prefix: String
    ) -> (word: String, range: NSRange)? {
        guard wordEnd > prefix.startIndex else { return nil }
        let lastLetter = prefix.index(before: wordEnd)
        guard prefix[lastLetter].isLetter else { return nil }

        var wordStart = wordEnd
        while wordStart > prefix.startIndex {
            let previous = prefix.index(before: wordStart)
            if !prefix[previous].isLetter { break }
            wordStart = previous
        }

        let word = String(prefix[wordStart..<wordEnd])
        guard !word.isEmpty else { return nil }
        return (word, NSRange(wordStart..<wordEnd, in: prefix))
    }
}
