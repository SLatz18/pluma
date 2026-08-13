import Carbon.HIToolbox
import XCTest
@testable import Pluma

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

    func testKeyWhileHeldPassesWithCapsChord() {
        var machine = CapsLockStateMachine()
        _ = machine.handle(.capsDown)
        XCTAssertEqual(machine.handle(.otherKey), .passWithCapsChord)
        XCTAssertEqual(machine.handle(.otherKey), .passWithCapsChord)
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

    func testAligningCapsChordFlipsShift() {
        let three = GlobalShortcut.default
        XCTAssertTrue(three.isCapsChord)
        let four = three.aligningCapsChord(includesShift: true)
        XCTAssertTrue(four.isCapsChord)
        XCTAssertNotEqual(three.carbonModifiers, four.carbonModifiers)
        let back = four.aligningCapsChord(includesShift: false)
        XCTAssertEqual(back.carbonModifiers, three.carbonModifiers)
    }

    func testNonCapsShortcutIsUnchangedByAlign() {
        let custom = GlobalShortcut(
            keyCode: 0,
            carbonModifiers: UInt32(cmdKey | shiftKey),
            display: "⇧⌘A"
        )
        let aligned = custom.aligningCapsChord(includesShift: true)
        XCTAssertEqual(aligned, custom)
    }
}
