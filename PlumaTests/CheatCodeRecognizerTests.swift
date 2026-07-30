import XCTest
@testable import Pluma

final class CheatCodeRecognizerTests: XCTestCase {
    private let up: UInt16 = 126
    private let down: UInt16 = 125
    private let left: UInt16 = 123
    private let right: UInt16 = 124
    private let escape: UInt16 = 53

    /// Feeds keys one tick apart unless a gap is given, returning true if any
    /// press completed the sequence.
    private func feed(
        _ keys: [UInt16],
        into recognizer: inout CheatCodeRecognizer,
        startingAt start: ContinuousClock.Instant = .now,
        gap: Duration = .milliseconds(100)
    ) -> Bool {
        var matched = false
        var now = start
        for key in keys {
            if recognizer.accept(keyCode: key, at: now) { matched = true }
            now = now.advanced(by: gap)
        }
        return matched
    }

    private var code: [UInt16] { CheatCodeRecognizer.sequence }

    func testFullSequenceUnlocks() {
        var recognizer = CheatCodeRecognizer()
        XCTAssertTrue(feed(code, into: &recognizer))
    }

    func testSequenceIsArrowsOnly() {
        // Arrows never insert characters, which is what lets the code be typed
        // with a text field focused.
        XCTAssertEqual(CheatCodeRecognizer.sequence.count, 8)
        XCTAssertTrue(CheatCodeRecognizer.sequence.allSatisfy { [123, 124, 125, 126].contains($0) })
    }

    func testPartialSequenceDoesNotUnlock() {
        var recognizer = CheatCodeRecognizer()
        XCTAssertFalse(feed(Array(code.dropLast()), into: &recognizer))
    }

    func testWrongKeyMidwayResets() {
        var recognizer = CheatCodeRecognizer()
        XCTAssertFalse(feed([up, up, down, escape, down, left, right, left, right], into: &recognizer))
    }

    func testWrongKeyThatStartsTheSequenceBeginsAFreshAttempt() {
        var recognizer = CheatCodeRecognizer()
        // A stray third ↑ ends the first attempt but starts the next one, so
        // the code still lands without lifting hands.
        XCTAssertTrue(feed([up, up, up] + Array(code.dropFirst()), into: &recognizer))
    }

    func testPauseLongerThanTheTimeoutExpiresAPartialAttempt() {
        var recognizer = CheatCodeRecognizer()
        let start = ContinuousClock.Instant.now

        _ = feed(Array(code.prefix(4)), into: &recognizer, startingAt: start)
        // Resume the remaining keys well after the timeout.
        let late = start.advanced(by: .seconds(30))
        XCTAssertFalse(feed(Array(code.dropFirst(4)), into: &recognizer, startingAt: late))
    }

    func testPauseShorterThanTheTimeoutKeepsProgress() {
        var recognizer = CheatCodeRecognizer()
        let start = ContinuousClock.Instant.now

        _ = feed(Array(code.prefix(4)), into: &recognizer, startingAt: start)
        let soon = start.advanced(by: .milliseconds(1_500))
        XCTAssertTrue(feed(Array(code.dropFirst(4)), into: &recognizer, startingAt: soon))
    }

    // Re-entering the code is how developer mode is turned back off.
    func testSequenceMatchesAgainImmediatelyAfterUnlocking() {
        var recognizer = CheatCodeRecognizer()
        XCTAssertTrue(feed(code, into: &recognizer))
        XCTAssertTrue(feed(code, into: &recognizer))
    }

    func testUnrelatedTypingNeverMatches() {
        var recognizer = CheatCodeRecognizer()
        XCTAssertFalse(feed([escape, 0, 1, 2, 36, 49, escape], into: &recognizer))
    }
}
