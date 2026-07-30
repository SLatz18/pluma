import XCTest
@testable import Pluma

final class SpellCorrectionTests: XCTestCase {
    func testFinishedWordRequiresTrailingBoundary() {
        XCTAssertNil(SpellCorrection.finishedWordRange(inPrefix: "teh"))
        XCTAssertNil(SpellCorrection.finishedWordRange(inPrefix: ""))
        XCTAssertNil(SpellCorrection.finishedWordRange(inPrefix: " "))
    }

    func testFinishedWordAfterSpace() {
        let result = SpellCorrection.finishedWordRange(inPrefix: "Please fix teh ")
        XCTAssertEqual(result?.word, "teh")
        XCTAssertEqual(result?.range.location, 11)
        XCTAssertEqual(result?.range.length, 3)
    }

    func testFinishedWordAfterPunctuation() {
        let result = SpellCorrection.finishedWordRange(inPrefix: "teh.")
        XCTAssertEqual(result?.word, "teh")
        XCTAssertEqual(result?.range, NSRange(location: 0, length: 3))
    }

    func testFinishedWordSkipsTrailingNonLetters() {
        let result = SpellCorrection.finishedWordRange(inPrefix: "recieve... ")
        XCTAssertEqual(result?.word, "recieve")
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

    func testPreferenceDefaultsOnAndRespectsExplicitOff() {
        let suite = "pluma.tests.spellCorrection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(Preferences.spellCorrectionEnabled(from: defaults))

        Preferences.setSpellCorrectionEnabled(false, to: defaults)
        XCTAssertFalse(Preferences.spellCorrectionEnabled(from: defaults))

        Preferences.setSpellCorrectionEnabled(true, to: defaults)
        XCTAssertTrue(Preferences.spellCorrectionEnabled(from: defaults))
    }
}
