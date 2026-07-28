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

    func testEmptyTranscriptInsertsNothing() {
        XCTAssertEqual(DictationTranscript.insertionText("   ", precededBy: "hello"), "")
    }

    func testShortTranscriptsSkipCleanup() {
        XCTAssertFalse(DictationTranscript.isWorthCleaningUp("yes"))
        XCTAssertFalse(DictationTranscript.isWorthCleaningUp("sounds good"))
        XCTAssertTrue(DictationTranscript.isWorthCleaningUp("on my way now"))
    }
}
