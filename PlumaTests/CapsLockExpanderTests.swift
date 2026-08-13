import Carbon.HIToolbox
import XCTest
@testable import Pluma

final class CapsLockExpanderTests: XCTestCase {
    private let t0: TimeInterval = 1_000

    func testOrdinaryTypingPassesThroughUnmodified() {
        var machine = CapsLockStateMachine()
        XCTAssertEqual(machine.handle(.otherKeyDown, at: t0), .passUnmodified)
        XCTAssertEqual(machine.handle(.otherKeyUp, at: t0 + 0.01), .passUnmodified)
        XCTAssertFalse(machine.capsHeld)
    }

    func testCapsDownIsConsumedAndArms() {
        var machine = CapsLockStateMachine()
        XCTAssertEqual(machine.handle(.capsDown, at: t0), .consume)
        XCTAssertTrue(machine.capsHeld)
    }

    func testKeyWhileHeldPassesWithCapsChord() {
        var machine = CapsLockStateMachine()
        _ = machine.handle(.capsDown, at: t0)
        XCTAssertEqual(machine.handle(.otherKeyDown, at: t0 + 0.05), .passWithCapsChord)
        XCTAssertEqual(machine.handle(.otherKeyUp, at: t0 + 0.06), .passWithCapsChord)
    }

    func testReleaseAfterChordIsConsumedSilently() {
        var machine = CapsLockStateMachine()
        _ = machine.handle(.capsDown, at: t0)
        _ = machine.handle(.otherKeyDown, at: t0 + 0.05)
        XCTAssertEqual(machine.handle(.capsUp, at: t0 + 0.1), .consume)
        XCTAssertFalse(machine.capsHeld)
    }

    func testQuickTapTogglesCapsLock() {
        var machine = CapsLockStateMachine()
        _ = machine.handle(.capsDown, at: t0)
        XCTAssertEqual(
            machine.handle(.capsUp, at: t0 + 0.1),
            .consumeAndToggleCapsLock
        )
        XCTAssertFalse(machine.capsHeld)
    }

    func testSlowHoldWithoutChordDoesNotToggle() {
        var machine = CapsLockStateMachine()
        _ = machine.handle(.capsDown, at: t0)
        XCTAssertEqual(
            machine.handle(.capsUp, at: t0 + 0.5),
            .consume
        )
    }

    func testTapToggleCanBeDisabled() {
        var machine = CapsLockStateMachine()
        machine.tapTogglesCapsLock = false
        _ = machine.handle(.capsDown, at: t0)
        XCTAssertEqual(machine.handle(.capsUp, at: t0 + 0.1), .consume)
    }

    func testKeyUpBeforeCapsDoesNotSuppressTap() {
        // Hold A, press Caps, release A, release Caps quickly → still a tap.
        var machine = CapsLockStateMachine()
        _ = machine.handle(.otherKeyDown, at: t0)
        _ = machine.handle(.capsDown, at: t0 + 0.05)
        XCTAssertEqual(machine.handle(.otherKeyUp, at: t0 + 0.06), .passWithCapsChord)
        XCTAssertEqual(
            machine.handle(.capsUp, at: t0 + 0.1),
            .consumeAndToggleCapsLock
        )
    }

    func testForceReleaseClearsStrandedHold() {
        var machine = CapsLockStateMachine()
        _ = machine.handle(.capsDown, at: t0)
        XCTAssertEqual(machine.handle(.forceRelease, at: t0 + 0.05), .passUnmodified)
        XCTAssertFalse(machine.capsHeld)
        XCTAssertEqual(machine.handle(.otherKeyDown, at: t0 + 0.1), .passUnmodified)
    }

    func testMaxHoldCeilingAbandonsStrandedModifier() {
        var machine = CapsLockStateMachine()
        machine.maxHold = 0.2
        _ = machine.handle(.capsDown, at: t0)
        // No capsUp — next key after ceiling must pass unmodified.
        XCTAssertEqual(machine.handle(.otherKeyDown, at: t0 + 0.5), .passUnmodified)
        XCTAssertFalse(machine.capsHeld)
    }

    func testTypingResumesAfterRelease() {
        var machine = CapsLockStateMachine()
        _ = machine.handle(.capsDown, at: t0)
        _ = machine.handle(.otherKeyDown, at: t0 + 0.05)
        _ = machine.handle(.capsUp, at: t0 + 0.1)
        XCTAssertEqual(machine.handle(.otherKeyDown, at: t0 + 0.2), .passUnmodified)
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
