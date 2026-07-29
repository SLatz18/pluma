import XCTest
@testable import Rewrite

final class DictationTranscriptTests: XCTestCase {
    func testAssembleCollapsesSegmentWhitespace() {
        XCTAssertEqual(
            DictationTranscript.assemble("  the quick   brown\nfox  "),
            "the quick brown fox"
        )
    }

    func testAssembleOfEmptyInputIsEmpty() {
        XCTAssertEqual(DictationTranscript.assemble("   \n  "), "")
    }

    func testMidSentenceCaretGetsALeadingSpace() {
        XCTAssertEqual(
            DictationTranscript.insertionText("world", precededBy: "hello"),
            " world"
        )
    }

    func testCaretAfterWhitespaceGetsNoLeadingSpace() {
        XCTAssertEqual(
            DictationTranscript.insertionText("world", precededBy: "hello "),
            "world"
        )
        XCTAssertEqual(
            DictationTranscript.insertionText("world", precededBy: "hello\n"),
            "world"
        )
    }

    func testCaretAfterOpeningCharacterGetsNoLeadingSpace() {
        XCTAssertEqual(
            DictationTranscript.insertionText("world", precededBy: "(" ),
            "world"
        )
        XCTAssertEqual(
            DictationTranscript.insertionText("world", precededBy: "\""),
            "world"
        )
    }

    func testEmptyFieldGetsNoLeadingSpace() {
        XCTAssertEqual(DictationTranscript.insertionText("world", precededBy: ""), "world")
        XCTAssertEqual(DictationTranscript.insertionText("world", precededBy: nil), "world")
    }

    // When the caret text is unreadable, the only prefix available is the final
    // character of what we last inserted, which is how sentence joins get their
    // space back in fields that report no caret at all.
    func testSentenceEndingPrefixGetsALeadingSpace() {
        XCTAssertEqual(
            DictationTranscript.insertionText("Is there a way", precededBy: "."),
            " Is there a way"
        )
        XCTAssertEqual(DictationTranscript.insertionText("Also", precededBy: "?"), " Also")
    }

    func testEmptyTranscriptInsertsNothing() {
        XCTAssertEqual(DictationTranscript.insertionText("   ", precededBy: "hello"), "")
    }

    func testDictatedFragmentLosesItsTrailingPeriod() {
        XCTAssertEqual(DictationTranscript.withoutFragmentPeriod("Scott."), "Scott")
        XCTAssertEqual(DictationTranscript.withoutFragmentPeriod("Scott Latz."), "Scott Latz")
    }

    func testSentencesKeepTheirPunctuation() {
        XCTAssertEqual(
            DictationTranscript.withoutFragmentPeriod("Let us ship it today."),
            "Let us ship it today."
        )
    }

    // Intonation produced these, and an ellipsis is deliberate, so a fragment
    // keeps them where it would lose a plain period.
    func testFragmentKeepsDeliberatePunctuation() {
        XCTAssertEqual(DictationTranscript.withoutFragmentPeriod("Scott?"), "Scott?")
        XCTAssertEqual(DictationTranscript.withoutFragmentPeriod("Scott!"), "Scott!")
        XCTAssertEqual(DictationTranscript.withoutFragmentPeriod("Scott..."), "Scott...")
    }

    // Paragraph breaks help a dictated document and wreck a dictated message, so
    // the directive changes with length rather than always asking for them.
    func testShortDictationIsToldToStaySingleParagraph() {
        let directive = PromptComposer.dictationDirective(for: "let us ship this tonight")
        XCTAssertTrue(directive.contains("single paragraph"))
        XCTAssertFalse(directive.contains("Break the result into paragraphs"))
    }

    func testLongDictationIsAllowedParagraphs() {
        let long = Array(repeating: "word", count: PromptComposer.paragraphWordThreshold)
            .joined(separator: " ")
        let directive = PromptComposer.dictationDirective(for: long)
        XCTAssertTrue(directive.contains("Break the result into paragraphs"))
        XCTAssertFalse(directive.contains("single paragraph"))
    }

    func testShortTranscriptsSkipCleanup() {
        XCTAssertFalse(DictationTranscript.isWorthCleaningUp("yes"))
        XCTAssertFalse(DictationTranscript.isWorthCleaningUp("sounds good"))
        XCTAssertTrue(DictationTranscript.isWorthCleaningUp("on my way now"))
    }
}
