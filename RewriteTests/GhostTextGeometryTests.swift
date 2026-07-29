import XCTest
@testable import Rewrite

final class GhostTextGeometryTests: XCTestCase {

    // MARK: Font size

    func testFontSizeUndoesTheLineHeightRatio() {
        // A 16 pt line box is what the system font at 13 pt occupies.
        XCTAssertEqual(GhostTextGeometry.fontSize(forCaretHeight: 16), 13)
        XCTAssertEqual(GhostTextGeometry.fontSize(forCaretHeight: 20), 16)
    }

    func testFontSizeFallsBackForImplausibleCaretHeights() {
        for height in [CGFloat(0), -12, 6, 200, 4_000, .nan] {
            XCTAssertEqual(
                GhostTextGeometry.fontSize(forCaretHeight: height),
                GhostTextGeometry.defaultFontSize,
                "height \(height) should fall back"
            )
        }
    }

    func testFontSizeIsClampedAtBothEnds() {
        XCTAssertEqual(GhostTextGeometry.fontSize(forCaretHeight: 7), 9)
        XCTAssertEqual(GhostTextGeometry.fontSize(forCaretHeight: 190), 48)
    }

    // MARK: Baseline

    func testBaselineSitsAboveTheBottomOfTheLineBox() {
        let caret = CGRect(x: 40, y: 100, width: 1, height: 20)
        XCTAssertEqual(GhostTextGeometry.baselineY(forCaretRect: caret), 116)
    }

    // MARK: Width budget

    func testWidthBudgetIsTheRoomLeftInTheField() {
        let budget = GhostTextGeometry.widthBudget(
            caretMaxX: 100, fieldMaxX: 400, screenMaxX: 1_000
        )
        XCTAssertEqual(budget, 400 - 100 - GhostTextGeometry.trailingGap)
    }

    func testWidthBudgetFallsBackToTheScreenWithoutAFieldFrame() {
        let budget = GhostTextGeometry.widthBudget(
            caretMaxX: 100, fieldMaxX: nil, screenMaxX: 1_000
        )
        XCTAssertEqual(budget, 1_000 - 100 - GhostTextGeometry.trailingGap)
    }

    func testWidthBudgetNeverExceedsTheScreen() {
        // A field can extend past the display it is mostly on.
        let budget = GhostTextGeometry.widthBudget(
            caretMaxX: 100, fieldMaxX: 5_000, screenMaxX: 1_000
        )
        XCTAssertEqual(budget, 1_000 - 100 - GhostTextGeometry.trailingGap)
    }

    func testWidthBudgetHasAFloorSoNarrowFieldsStayReadable() {
        let budget = GhostTextGeometry.widthBudget(
            caretMaxX: 396, fieldMaxX: 400, screenMaxX: 1_000
        )
        XCTAssertEqual(budget, 60)
    }

    // MARK: Direction

    func testLatinTextIsLeftToRight() {
        XCTAssertFalse(GhostTextGeometry.isRightToLeft("hello there"))
    }

    func testHebrewAndArabicAreRightToLeft() {
        XCTAssertTrue(GhostTextGeometry.isRightToLeft("שלום"))
        XCTAssertTrue(GhostTextGeometry.isRightToLeft("مرحبا"))
    }

    func testLeadingNeutralsDoNotDecideDirection() {
        XCTAssertTrue(GhostTextGeometry.isRightToLeft("  \"שלום"))
        XCTAssertFalse(GhostTextGeometry.isRightToLeft("123 hello"))
    }

    func testFirstStrongCharacterWins() {
        XCTAssertFalse(GhostTextGeometry.isRightToLeft("email שלום"))
    }

    func testArabicIndicDigitsAreNotStrongDirection() {
        XCTAssertFalse(GhostTextGeometry.isRightToLeft("٢٠٢٦ hello"))
    }

    func testEmptyTextIsLeftToRight() {
        XCTAssertFalse(GhostTextGeometry.isRightToLeft(""))
    }
}

final class GhostTextEligibilityTests: XCTestCase {
    private let precise = CaretGeometry(rect: CGRect(x: 40, y: 100, width: 1, height: 17), source: .exactCaret)
    private let lineLevel = CaretGeometry(rect: CGRect(x: 40, y: 100, width: 1, height: 17), source: .lineBounds)

    func testCaretAtEndOfTextAllowsGhostText() {
        let eligibility = GhostTextEligibility.of(text: "hello there", caretLocation: 11)
        XCTAssertTrue(eligibility.allows(precise))
    }

    func testMidLineCaretDoesNotAllowGhostText() {
        let eligibility = GhostTextEligibility.of(text: "hello there", caretLocation: 5)
        XCTAssertFalse(eligibility.allows(precise))
    }

    // A line-level rect is already the end of its line, which is all the
    // end-of-text check was ever standing in for.
    func testLineLevelCaretAllowsGhostTextMidText() {
        let eligibility = GhostTextEligibility.of(text: "hello there", caretLocation: 5)
        XCTAssertTrue(eligibility.allows(lineLevel))
    }

    func testRightToLeftIsRefusedNoMatterHowTheCaretWasFound() {
        let eligibility = GhostTextEligibility.of(text: "שלום", caretLocation: 4)
        XCTAssertFalse(eligibility.allows(precise))
        XCTAssertFalse(eligibility.allows(lineLevel))
    }

    func testUnknownRefusesPreciseCarets() {
        XCTAssertFalse(GhostTextEligibility.unknown.allows(precise))
    }

    func testEmptyFieldCountsAsEndOfText() {
        XCTAssertTrue(GhostTextEligibility.of(text: "", caretLocation: 0).allows(precise))
    }
}
