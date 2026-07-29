import XCTest
@testable import Rewrite

// Canned Accessibility geometry, so the probe ladder can be exercised without a
// live app on screen.
private struct StubProbe: CaretProbing {
    var elementFrame: CGRect? = nil
    var lineNumber: Int? = nil
    var lineRange: CFRange? = nil
    var bounds: (CFRange) -> CGRect?

    func boundsForRange(_ range: CFRange) -> CGRect? { bounds(range) }
    func insertionPointLineNumber() -> Int? { lineNumber }
    func rangeForLine(_ line: Int) -> CFRange? { lineRange }
}

private let field = CGRect(x: 100, y: 200, width: 400, height: 60)

final class CaretResolverTests: XCTestCase {

    // MARK: Probe ordering

    func testExactCaretIsPreferred() {
        let caret = CGRect(x: 180, y: 210, width: 1, height: 17)
        let probe = StubProbe(elementFrame: field, bounds: { range in
            range.length == 0 ? caret : nil
        })

        let resolved = CaretResolver.resolve(location: 12, using: probe)
        XCTAssertEqual(resolved?.rect, caret)
        XCTAssertEqual(resolved?.isPrecise, true)
    }

    // The Chromium case the ladder exists for: a zero-length range at the end
    // of the text answers with a degenerate rect at the screen's corner, while
    // the character before the caret reports correctly.
    func testFallsBackToTheCharacterBeforeTheCaret() {
        let garbage = CGRect(x: 0, y: 1_079, width: 0, height: 0)
        let previousCharacter = CGRect(x: 170, y: 210, width: 9, height: 17)
        let probe = StubProbe(elementFrame: field, bounds: { range in
            range.length == 0 ? garbage : previousCharacter
        })

        let resolved = CaretResolver.resolve(location: 12, using: probe)
        XCTAssertEqual(resolved?.rect.minX, previousCharacter.maxX)
        XCTAssertEqual(resolved?.rect.minY, previousCharacter.minY)
        XCTAssertEqual(resolved?.rect.height, previousCharacter.height)
        XCTAssertEqual(resolved?.isPrecise, true)
    }

    func testCaretAtStartOfTextSkipsThePrecedingCharacterProbe() {
        var askedForCharacterProbe = false
        let probe = StubProbe(elementFrame: field, bounds: { range in
            if range.length == 1 { askedForCharacterProbe = true }
            return nil
        })

        XCTAssertNil(CaretResolver.resolve(location: 0, using: probe))
        XCTAssertFalse(askedForCharacterProbe)
    }

    func testFallsBackToTheLineBounds() {
        let line = CGRect(x: 110, y: 232, width: 260, height: 17)
        let probe = StubProbe(
            elementFrame: field,
            lineNumber: 2,
            lineRange: CFRange(location: 40, length: 30),
            bounds: { range in
                range.location == 40 && range.length == 30 ? line : nil
            }
        )

        let resolved = CaretResolver.resolve(location: 55, using: probe)
        XCTAssertEqual(resolved?.rect.minX, line.maxX)
        XCTAssertEqual(resolved?.rect.height, line.height)
        // The line is right but the column is inferred, and callers treat that
        // as "the caret is at the end of its line".
        XCTAssertEqual(resolved?.isPrecise, false)
    }

    func testReturnsNilWhenEveryProbeFails() {
        let probe = StubProbe(elementFrame: field, bounds: { _ in nil })
        XCTAssertNil(CaretResolver.resolve(location: 12, using: probe))
    }

    func testLineFallbackNeedsBothTheLineNumberAndItsRange() {
        let probe = StubProbe(
            elementFrame: field,
            lineNumber: 2,
            lineRange: nil,
            bounds: { range in
                // Only the line range answers; the caret probes come up empty.
                range.location == 40 ? CGRect(x: 110, y: 232, width: 260, height: 17) : nil
            }
        )
        XCTAssertNil(CaretResolver.resolve(location: 12, using: probe))
    }

    // MARK: Plausibility

    func testZeroHeightRectIsRejected() {
        XCTAssertFalse(
            CaretResolver.isPlausible(CGRect(x: 180, y: 210, width: 1, height: 0), in: field)
        )
    }

    func testRectOutsideTheFieldIsRejected() {
        XCTAssertFalse(
            CaretResolver.isPlausible(CGRect(x: 0, y: 1_079, width: 1, height: 17), in: field)
        )
    }

    func testRectJustOutsideTheFieldEdgeIsTolerated() {
        // Fields round their own frames; a few points of slop is not garbage.
        XCTAssertTrue(
            CaretResolver.isPlausible(CGRect(x: 496, y: 210, width: 1, height: 17), in: field)
        )
    }

    func testWithoutAFieldFrameOnlyTheRectItselfIsJudged() {
        XCTAssertTrue(
            CaretResolver.isPlausible(CGRect(x: 0, y: 1_079, width: 1, height: 17), in: nil)
        )
        XCTAssertFalse(
            CaretResolver.isPlausible(CGRect(x: 0, y: 0, width: 1, height: 0), in: nil)
        )
    }
}
