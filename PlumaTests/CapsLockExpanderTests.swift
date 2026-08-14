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

    // Pluma's own synthetic ⌘C/⌘V must pass the tap untouched while Caps is
    // held — and must not advance the machine, so the hold survives them.
    func testSyntheticEventPassesUntouchedWhileCapsHeld() {
        let state = CapsTapState()
        XCTAssertEqual(state.verdict(type: .keyDown, keyCode: Int64(kVK_F18)), .consume)
        XCTAssertTrue(state.isCapsHeld())
        XCTAssertEqual(
            state.verdict(type: .keyDown, keyCode: Int64(kVK_ANSI_C), isSynthetic: true),
            .passUnmodified
        )
        XCTAssertEqual(
            state.verdict(type: .keyUp, keyCode: Int64(kVK_ANSI_C), isSynthetic: true),
            .passUnmodified
        )
        XCTAssertTrue(state.isCapsHeld())
        // A real key while held still gets the chord.
        XCTAssertEqual(
            state.verdict(type: .keyDown, keyCode: Int64(kVK_ANSI_L)),
            .passWithCapsChord
        )
    }

    func testSyntheticMarkerRoundTrip() {
        guard
            let marked = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true),
            let unmarked = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true)
        else { return XCTFail("could not create CGEvents") }
        SyntheticEventMarker.mark(marked)
        XCTAssertTrue(SyntheticEventMarker.isPlumaEvent(marked))
        XCTAssertFalse(SyntheticEventMarker.isPlumaEvent(unmarked))
    }

    func testIsCapsHeldClearsOnRelease() {
        let state = CapsTapState()
        _ = state.verdict(type: .keyDown, keyCode: Int64(kVK_F18))
        _ = state.verdict(type: .keyDown, keyCode: Int64(kVK_ANSI_L))
        XCTAssertTrue(state.isCapsHeld())
        _ = state.verdict(type: .keyUp, keyCode: Int64(kVK_F18))
        XCTAssertFalse(state.isCapsHeld())
    }

    // A chord fires once per physical press: OS autorepeat of the chorded key
    // must be swallowed, not re-sent with the Caps chord (a held ⇪2 kept
    // reopening the screenshot tool).
    func testAutorepeatWhileHeldIsConsumedNotRefired() {
        var machine = CapsLockStateMachine()
        _ = machine.handle(.capsDown, at: t0)
        XCTAssertEqual(machine.handle(.otherKeyDown, at: t0 + 0.05), .passWithCapsChord)
        XCTAssertEqual(machine.handle(.otherKeyRepeat, at: t0 + 0.4), .consume)
        XCTAssertEqual(machine.handle(.otherKeyRepeat, at: t0 + 0.5), .consume)
        XCTAssertEqual(machine.handle(.otherKeyUp, at: t0 + 0.6), .passWithCapsChord)
        // The repeat marked the hold as used, so release must not toggle Caps Lock.
        XCTAssertEqual(machine.handle(.capsUp, at: t0 + 0.7), .consume)
    }

    func testAutorepeatWithoutCapsPassesUnmodified() {
        var machine = CapsLockStateMachine()
        XCTAssertEqual(machine.handle(.otherKeyDown, at: t0), .passUnmodified)
        XCTAssertEqual(machine.handle(.otherKeyRepeat, at: t0 + 0.4), .passUnmodified)
    }

    func testDistinctPressesEachFireTheChord() {
        var machine = CapsLockStateMachine()
        _ = machine.handle(.capsDown, at: t0)
        for i in 0..<4 {
            let at = t0 + 0.1 + Double(i) * 0.2
            XCTAssertEqual(machine.handle(.otherKeyDown, at: at), .passWithCapsChord)
            XCTAssertEqual(machine.handle(.otherKeyUp, at: at + 0.05), .passWithCapsChord)
        }
    }

    func testVerdictRoutesAutorepeatKeyDowns() {
        let state = CapsTapState()
        _ = state.verdict(type: .keyDown, keyCode: Int64(kVK_F18))
        XCTAssertEqual(
            state.verdict(type: .keyDown, keyCode: Int64(kVK_ANSI_2)),
            .passWithCapsChord
        )
        XCTAssertEqual(
            state.verdict(type: .keyDown, keyCode: Int64(kVK_ANSI_2), isAutorepeat: true),
            .consume
        )
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

    // MARK: - hidutil dump parsing

    /// Real `hidutil property --get UserKeyMapping` output on macOS 26. Note the
    /// key order: Dst comes first. Reading the pair positionally made every poll
    /// think the mapping was missing and re-apply it every few seconds.
    func testParsesDumpWithDstBeforeSrc() {
        let dump = """
        (
                {
                HIDKeyboardModifierMappingDst = 30064771181;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        """
        let entries = CapsLockHIDRemap.entries(fromDump: dump)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.HIDKeyboardModifierMappingSrc, CapsLockHIDRemap.capsLockUsage)
        XCTAssertEqual(entries.first?.HIDKeyboardModifierMappingDst, CapsLockHIDRemap.f18Usage)
    }

    /// A second remap must survive: `apply` derives the crash-restore snapshot
    /// from this parse, so a dropped entry would silently wipe the user's remap.
    func testParsesMultipleEntriesWithoutCrossPairing() {
        let dump = """
        (
                {
                HIDKeyboardModifierMappingDst = 30064771113;
                HIDKeyboardModifierMappingSrc = 30064771110;
            },
                {
                HIDKeyboardModifierMappingDst = 30064771181;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        """
        let entries = CapsLockHIDRemap.entries(fromDump: dump)
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.contains(
            .init(
                HIDKeyboardModifierMappingSrc: CapsLockHIDRemap.capsLockUsage,
                HIDKeyboardModifierMappingDst: CapsLockHIDRemap.f18Usage
            )
        ))
        XCTAssertTrue(entries.contains(
            .init(HIDKeyboardModifierMappingSrc: 30_064_771_110, HIDKeyboardModifierMappingDst: 30_064_771_113)
        ))
    }

    func testParsesHexAndJSONForms() {
        let hexDump = """
        (
                {
                HIDKeyboardModifierMappingSrc = 0x700000039;
                HIDKeyboardModifierMappingDst = 0x70000006D;
            }
        )
        """
        XCTAssertEqual(
            CapsLockHIDRemap.entries(fromDump: hexDump).first?.HIDKeyboardModifierMappingSrc,
            CapsLockHIDRemap.capsLockUsage
        )

        let json = """
        [{"HIDKeyboardModifierMappingSrc":30064771129,"HIDKeyboardModifierMappingDst":30064771181}]
        """
        XCTAssertEqual(
            CapsLockHIDRemap.entries(fromDump: json).first?.HIDKeyboardModifierMappingDst,
            CapsLockHIDRemap.f18Usage
        )
    }

    func testEmptyDumpFormsParseAsNoEntries() {
        for text in ["", "()", "null", "(null)", "(\n)"] {
            XCTAssertTrue(
                CapsLockHIDRemap.entries(fromDump: text).isEmpty,
                "expected no entries for \(text.debugDescription)"
            )
        }
    }
}
