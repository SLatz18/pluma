import Foundation

// A finished misspelling immediately before the caret, plus the dictionary's
// top guess. Absolute UTF-16 locations match Accessibility selection ranges.
struct SpellCorrectionOffer: Equatable, Sendable {
    let misspelled: String
    let replacement: String
    let wordLocation: Int
    let wordLength: Int
}

enum SpellCorrection {
    // The caret sits after whitespace or punctuation that closed a word. The
    // alphabetic run before that boundary is the finished word — "teh " and
    // "teh." both yield "teh"; a caret still inside the word yields nothing.
    static func finishedWordRange(inPrefix prefix: String) -> (word: String, range: NSRange)? {
        guard let last = prefix.last, !last.isLetter else { return nil }

        var wordEnd = prefix.endIndex
        while wordEnd > prefix.startIndex {
            let previous = prefix.index(before: wordEnd)
            if prefix[previous].isLetter { break }
            wordEnd = previous
        }
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

    // Pure assembly so tests can inject misspell / guess answers without
    // standing up NSSpellChecker. The word range in the prefix is already
    // absolute in the field: text-before-caret starts at location 0.
    static func offer(
        prefix: String,
        isMisspelled: (String) -> Bool,
        guessesFor: (String) -> [String]
    ) -> SpellCorrectionOffer? {
        guard let (word, range) = finishedWordRange(inPrefix: prefix) else { return nil }
        guard isMisspelled(word) else { return nil }
        guard
            let replacement = guessesFor(word).first,
            !replacement.isEmpty,
            replacement.caseInsensitiveCompare(word) != .orderedSame
        else { return nil }

        return SpellCorrectionOffer(
            misspelled: word,
            replacement: replacement,
            wordLocation: range.location,
            wordLength: range.length
        )
    }
}
