import XCTest
@testable import Rewrite

final class CapsLockExpanderTests: XCTestCase {

    func testOrdinaryTypingPassesThroughUnmodified() {
        var machine = CapsLockStateMachine()
        XCTAssertEqual(machine.handle(.otherKey), .passUnmodified)
        XCTAssertEqual(machine.handle(.otherKey), .passUnmodified)
        XCTAssertFalse(machine.capsHeld)
    }

    func testCapsDownIsConsumedAndArms() {
        var machine = CapsLockStateMachine()
        XCTAssertEqual(machine.handle(.capsDown), .consume)
        XCTAssertTrue(machine.capsHeld)
    }

    func testKeyWhileHeldPassesWithHyper() {
        var machine = CapsLockStateMachine()
        _ = machine.handle(.capsDown)
        XCTAssertEqual(machine.handle(.otherKey), .passWithHyper)
        XCTAssertEqual(machine.handle(.otherKey), .passWithHyper)
    }

    func testReleaseAfterChordIsConsumedSilently() {
        var machine = CapsLockStateMachine()
        _ = machine.handle(.capsDown)
        _ = machine.handle(.otherKey)
        XCTAssertEqual(machine.handle(.capsUp), .consume)
        XCTAssertFalse(machine.capsHeld)
    }

    func testTapWithoutChordIsConsumedSilently() {
        var machine = CapsLockStateMachine()
        _ = machine.handle(.capsDown)
        XCTAssertEqual(machine.handle(.capsUp), .consume)
        XCTAssertFalse(machine.capsHeld)
    }

    func testTypingResumesAfterRelease() {
        var machine = CapsLockStateMachine()
        _ = machine.handle(.capsDown)
        _ = machine.handle(.otherKey)
        _ = machine.handle(.capsUp)
        XCTAssertEqual(machine.handle(.otherKey), .passUnmodified)
    }
}
