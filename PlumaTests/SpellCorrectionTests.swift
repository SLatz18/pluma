import AppKit
import XCTest
@testable import Pluma

final class SpellCorrectionTests: XCTestCase {
    func testFinishedWordRequiresTrailingBoundary() {
        XCTAssertNil(SpellCorrection.finishedWordRange(inPrefix: "teh"))
        XCTAssertNil(SpellCorrection.finishedWordRange(inPrefix: "adminipera"))
        XCTAssertNil(SpellCorrection.finishedWordRange(inPrefix: "documenta"))
        XCTAssertNil(SpellCorrection.finishedWordRange(inPrefix: ""))
        XCTAssertNil(SpellCorrection.finishedWordRange(inPrefix: " "))
        XCTAssertNil(SpellCorrection.finishedWordRange(inPrefix: "..."))
    }

    func testFinishedWordAfterSpace() {
        let result = SpellCorrection.finishedWordRange(inPrefix: "Please fix teh ")
        XCTAssertEqual(result?.word, "teh")
        XCTAssertEqual(result?.range.location, 11)
        XCTAssertEqual(result?.range.length, 3)
    }

    func testFinishedWordAfterPunctuation() {
        XCTAssertEqual(SpellCorrection.finishedWordRange(inPrefix: "teh.")?.word, "teh")
        XCTAssertEqual(SpellCorrection.finishedWordRange(inPrefix: "teh!")?.word, "teh")
        XCTAssertEqual(SpellCorrection.finishedWordRange(inPrefix: "teh?")?.word, "teh")
        XCTAssertEqual(SpellCorrection.finishedWordRange(inPrefix: "teh,")?.word, "teh")
    }

    func testFinishedWordSkipsTrailingNonLetters() {
        let result = SpellCorrection.finishedWordRange(inPrefix: "recieve... ")
        XCTAssertEqual(result?.word, "recieve")
    }

    func testFinishedWordUsesOnlyTheTokenBeforeTheCaret() {
        let result = SpellCorrection.finishedWordRange(inPrefix: "teh draft is fine ")
        XCTAssertEqual(result?.word, "fine")
    }

    func testTrailingWordIncludesMidWordFragments() {
        let result = SpellCorrection.trailingWordRange(inPrefix: "Please review adminipera")
        XCTAssertEqual(result?.word, "adminipera")
        XCTAssertEqual(
            ("Please review adminipera" as NSString).substring(with: result!.range),
            "adminipera"
        )
    }

    func testCandidateAllowsMidWordOnlyWhenRequested() {
        let mid = SpellCorrection.candidateWordRange(
            inPrefix: "adminipera",
            allowMidWord: true,
            isMisspelled: { _ in true }
        )
        XCTAssertEqual(mid?.word, "adminipera")

        XCTAssertNil(
            SpellCorrection.candidateWordRange(
                inPrefix: "adminipera",
                allowMidWord: false,
                isMisspelled: { _ in true }
            )
        )
    }

    // Dictionary = finished words only (space/punct after). Apple Intelligence =
    // mid-word too. Same misspelling, two caret positions.
    func testSpaceVersusMidWordCandidateMatrix() {
        let cases: [(stem: String, mid: String, finished: String)] = [
            ("teh", "teh", "teh "),
            ("recieve", "Please review recieve", "Please review recieve "),
            ("adminipera", "Please review adminipera", "Please review adminipera "),
            ("administraton", "The administraton", "The administraton "),
            ("seperate", "seperate", "seperate."),
        ]

        for testCase in cases {
            // No trailing boundary: dictionary path must stay quiet.
            XCTAssertNil(
                SpellCorrection.candidateWordRange(
                    inPrefix: testCase.mid,
                    allowMidWord: false,
                    isMisspelled: { _ in true }
                ),
                "dictionary must ignore mid-word \(testCase.mid.debugDescription)"
            )

            // Mid-word AI path sees the stem.
            XCTAssertEqual(
                SpellCorrection.candidateWordRange(
                    inPrefix: testCase.mid,
                    allowMidWord: true,
                    isMisspelled: { _ in true }
                )?.word,
                testCase.stem,
                "AI mid-word \(testCase.mid.debugDescription)"
            )

            // After space/punct, both engines can see the same stem.
            XCTAssertEqual(
                SpellCorrection.candidateWordRange(
                    inPrefix: testCase.finished,
                    allowMidWord: false,
                    isMisspelled: { _ in true }
                )?.word,
                testCase.stem,
                "dictionary finished \(testCase.finished.debugDescription)"
            )
            XCTAssertEqual(
                SpellCorrection.candidateWordRange(
                    inPrefix: testCase.finished,
                    allowMidWord: true,
                    isMisspelled: { _ in true }
                )?.word,
                testCase.stem,
                "AI finished \(testCase.finished.debugDescription)"
            )
        }
    }

    func testTrailingWordRangeMatchesFinishedWordWhenBoundaryPresent() {
        for prefix in ["teh ", "teh.", "adminipera ", "recieve... "] {
            let finished = SpellCorrection.finishedWordRange(inPrefix: prefix)
            let trailing = SpellCorrection.trailingWordRange(inPrefix: prefix)
            XCTAssertEqual(finished?.word, trailing?.word, prefix)
            XCTAssertEqual(finished?.range, trailing?.range, prefix)
        }
    }

    func testLongMisspellingRangeInsideASentence() {
        let prefix = "The administraton of the fund "
        let result = SpellCorrection.finishedWordRange(inPrefix: prefix)
        XCTAssertEqual(result?.word, "fund")

        let mid = SpellCorrection.trailingWordRange(inPrefix: "The administraton")
        XCTAssertEqual(mid?.word, "administraton")
        XCTAssertEqual(mid?.range.length, "administraton".utf16.count)
    }

    func testOfferRequiresMisspellingAndDistinctGuess() {
        let offer = SpellCorrection.offer(
            prefix: "teh ",
            isMisspelled: { $0 == "teh" },
            guessesFor: { _ in ["the", "tea"] }
        )
        XCTAssertEqual(
            offer,
            SpellCorrectionOffer(
                misspelled: "teh",
                replacement: "the",
                wordLocation: 0,
                wordLength: 3
            )
        )
    }

    func testOfferFromModelReplacementSanitizesNoise() {
        let range = NSRange(location: 4, length: 10)
        let offer = SpellCorrection.offer(
            misspelled: "adminipera",
            range: range,
            replacement: "\"administration\" please"
        )
        XCTAssertEqual(offer?.replacement, "administration")
        XCTAssertEqual(offer?.wordLocation, 4)
        XCTAssertEqual(offer?.wordLength, 10)
    }

    func testSanitizedReplacementRejectsUnchangedWord() {
        XCTAssertEqual(
            SpellCorrection.sanitizedModelReplacement("Adminipera", forMisspelling: "adminipera"),
            ""
        )
        XCTAssertEqual(
            SpellCorrection.sanitizedModelReplacement("", forMisspelling: "teh"),
            ""
        )
    }

    func testSanitizedReplacementRejectsUnrelatedPrecedingCopies() {
        XCTAssertEqual(
            SpellCorrection.sanitizedModelReplacement("church", forMisspelling: "separ"),
            ""
        )
        XCTAssertEqual(
            SpellCorrection.sanitizedModelReplacement("separation", forMisspelling: "separ"),
            "separation"
        )
        XCTAssertEqual(
            SpellCorrection.sanitizedModelReplacement("the", forMisspelling: "teh"),
            "the"
        )
    }

    func testGrammarGatePrefersVerbAfterModalAdverb() {
        XCTAssertTrue(SpellCorrection.precedingLikelyNeedsVerb("She will carefully "))
        XCTAssertTrue(SpellCorrection.precedingLikelyNeedsVerb("to "))
        XCTAssertFalse(SpellCorrection.precedingLikelyNeedsVerb("church and state "))
        XCTAssertTrue(SpellCorrection.looksLikeNominalization("separation"))
        XCTAssertFalse(SpellCorrection.looksLikeNominalization("separate"))

        XCTAssertEqual(
            SpellCorrection.sanitizedModelReplacement(
                "separation",
                forMisspelling: "sepera",
                preceding: "She will carefully "
            ),
            ""
        )
        XCTAssertEqual(
            SpellCorrection.sanitizedModelReplacement(
                "separate",
                forMisspelling: "sepera",
                preceding: "She will carefully "
            ),
            "separate"
        )
        XCTAssertEqual(
            SpellCorrection.sanitizedModelReplacement(
                "separation",
                forMisspelling: "separ",
                preceding: "church and state "
            ),
            "separation"
        )
    }

    func testOfferUsesTopGuessOnly() {
        let offer = SpellCorrection.offer(
            prefix: "recieve ",
            isMisspelled: { _ in true },
            guessesFor: { _ in ["receive", "received", "receives"] }
        )
        XCTAssertEqual(offer?.replacement, "receive")
    }

    func testOfferIgnoresCorrectWords() {
        XCTAssertNil(
            SpellCorrection.offer(
                prefix: "the ",
                isMisspelled: { _ in false },
                guessesFor: { _ in ["the"] }
            )
        )
    }

    func testOfferIgnoresIdenticalGuess() {
        XCTAssertNil(
            SpellCorrection.offer(
                prefix: "teh ",
                isMisspelled: { _ in true },
                guessesFor: { _ in ["Teh"] }
            )
        )
    }

    func testOfferIgnoresEmptyGuessList() {
        XCTAssertNil(
            SpellCorrection.offer(
                prefix: "teh ",
                isMisspelled: { _ in true },
                guessesFor: { _ in [] }
            )
        )
    }

    func testOfferIgnoresMidWordPrefixForDictionaryPath() {
        XCTAssertNil(
            SpellCorrection.offer(
                prefix: "teh",
                isMisspelled: { _ in true },
                guessesFor: { _ in ["the"] }
            )
        )
    }

    func testPrecedingTextExcludesTheCandidateToken() {
        let prefix = "Hire a system admini"
        let range = SpellCorrection.trailingWordRange(inPrefix: prefix)!.range
        XCTAssertEqual(
            SpellCorrection.precedingText(inPrefix: prefix, wordRange: range),
            "Hire a system "
        )
    }

    func testSpellingPromptPutsPrecedingWordsBeforeTheToken() {
        let prompt = PromptComposer.spellingCorrectionUserPrompt(
            word: "admini",
            preceding: "oral medication "
        )
        XCTAssertTrue(prompt.contains("oral medication"))
        XCTAssertTrue(prompt.contains("<word>\nadmini\n</word>"))
        XCTAssertTrue(prompt.contains("Preceding words"))
    }

    func testPreferenceDefaultsOnAndRespectsExplicitOff() {
        let suite = "pluma.tests.spellCorrection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(Preferences.spellCorrectionEnabled(from: defaults))
        XCTAssertEqual(Preferences.spellCorrectionEngine(from: defaults), .appleIntelligence)

        Preferences.setSpellCorrectionEnabled(false, to: defaults)
        XCTAssertFalse(Preferences.spellCorrectionEnabled(from: defaults))

        Preferences.setSpellCorrectionEngine(.dictionary, to: defaults)
        XCTAssertEqual(Preferences.spellCorrectionEngine(from: defaults), .dictionary)

        Preferences.setSpellCorrectionEngine(.appleIntelligence, to: defaults)
        Preferences.setSpellCorrectionEnabled(true, to: defaults)
        XCTAssertTrue(Preferences.spellCorrectionEnabled(from: defaults))
        XCTAssertEqual(Preferences.spellCorrectionEngine(from: defaults), .appleIntelligence)
    }

    func testLiveDictionaryOffersCorrectionsForCommonMisspellings() throws {
        try skipUnlessEnglishSpellChecker()

        let cases: [(prefix: String, expected: String)] = [
            ("teh ", "the"),
            ("Please review teh ", "the"),
            ("recieve ", "receive"),
            ("seperate ", "separate"),
            ("occured ", "occurred"),
            ("definately ", "definitely"),
            ("administraton ", "administration"),
            ("adminstration ", "administration"),
            ("teh.", "the"),
        ]

        for testCase in cases {
            let offer = liveOffer(for: testCase.prefix)
            XCTAssertEqual(
                offer?.replacement.lowercased(),
                testCase.expected,
                "prefix \(testCase.prefix.debugDescription)"
            )
        }
    }

    func testLiveDictionaryCannotGuessAdminipera() throws {
        try skipUnlessEnglishSpellChecker()
        XCTAssertNil(liveOffer(for: "adminipera "))
        XCTAssertNil(
            SpellCorrection.candidateWordRange(
                inPrefix: "adminipera",
                allowMidWord: true,
                isMisspelled: { word in
                    let misspelled = NSSpellChecker.shared.checkSpelling(
                        of: word,
                        startingAt: 0,
                        language: NSSpellChecker.shared.language(),
                        wrap: false,
                        inSpellDocumentWithTag: 0,
                        wordCount: nil
                    )
                    return misspelled.location != NSNotFound
                }
            ).flatMap { word, range in
                SpellCorrection.offer(
                    misspelled: word,
                    range: range,
                    replacement: (
                        NSSpellChecker.shared.guesses(
                            forWordRange: NSRange(location: 0, length: (word as NSString).length),
                            in: word,
                            language: NSSpellChecker.shared.language(),
                            inSpellDocumentWithTag: 0
                        ) ?? []
                    ).first ?? ""
                )
            }
        )
    }

    func testLiveDictionaryDoesNotCorrectValidWords() throws {
        try skipUnlessEnglishSpellChecker()

        for prefix in ["the ", "receive ", "separate ", "administration ", "Please review the "] {
            XCTAssertNil(liveOffer(for: prefix), prefix)
        }
    }

    func testLiveDictionaryDoesNotCorrectMidWordFragments() throws {
        try skipUnlessEnglishSpellChecker()

        for prefix in ["teh", "recieve", "documenta", "adminipera"] {
            XCTAssertNil(liveOffer(for: prefix), prefix)
        }
    }

    private func liveOffer(for prefix: String) -> SpellCorrectionOffer? {
        SpellCorrection.offer(
            prefix: prefix,
            isMisspelled: { word in
                let misspelled = NSSpellChecker.shared.checkSpelling(
                    of: word,
                    startingAt: 0,
                    language: NSSpellChecker.shared.language(),
                    wrap: false,
                    inSpellDocumentWithTag: 0,
                    wordCount: nil
                )
                return misspelled.location != NSNotFound
            },
            guessesFor: { word in
                let range = NSRange(location: 0, length: (word as NSString).length)
                return NSSpellChecker.shared.guesses(
                    forWordRange: range,
                    in: word,
                    language: NSSpellChecker.shared.language(),
                    inSpellDocumentWithTag: 0
                ) ?? []
            }
        )
    }

    private func skipUnlessEnglishSpellChecker() throws {
        let language = NSSpellChecker.shared.language().lowercased()
        let offer = liveOffer(for: "teh ")
        guard language.hasPrefix("en") || offer?.replacement.lowercased() == "the" else {
            throw XCTSkip("English spell checker unavailable (language=\(language))")
        }
    }
}
