import Carbon.HIToolbox
import CoreGraphics
import XCTest
@testable import Pluma

/// ⇪4 → Spotlight clipboard history. The live half of this feature (does
/// Spotlight really show the history pane) cannot be asserted in a unit test,
/// so what is tested here is every decision that can be made wrong silently:
/// the tap ignoring pluma's own synthetic keystrokes, an already-open Spotlight
/// not being toggled shut, the window predicate, and the registered chord
/// tracking the Caps-with-Shift setting.
final class ClipboardHistoryControllerTests: XCTestCase {
    private let t0: TimeInterval = 1_000
    private let four = Int64(kVK_ANSI_4)

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ClipboardHistoryControllerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Constraint 2: the tap ignores its own synthetic events

    /// The recursion hazard: pluma's own ⌘4 goes back through its own tap. It
    /// has to pass untouched (no Caps chord ORed on, no hold disturbed) AND it
    /// must not slide the chord-debounce window, or a synthetic press would
    /// swallow the user's next real ⇪4.
    func testSyntheticFourIsIgnoredAndDoesNotSlideTheDebounceWindow() {
        let state = CapsTapState()
        XCTAssertEqual(state.verdict(type: .keyDown, keyCode: Int64(kVK_F18), at: t0), .consume)

        // A real ⇪4 fires and arms the 0.5 s debounce window.
        XCTAssertEqual(
            state.verdict(type: .keyDown, keyCode: four, at: t0),
            .passWithCapsChord
        )

        // pluma's own synthetic ⌘4, mid-window: passes untouched.
        XCTAssertEqual(
            state.verdict(type: .keyDown, keyCode: four, isSynthetic: true, at: t0 + 0.4),
            .passUnmodified
        )
        XCTAssertEqual(
            state.verdict(type: .keyUp, keyCode: four, isSynthetic: true, at: t0 + 0.4),
            .passUnmodified
        )
        // The Caps hold survives them — a synthetic event must not advance the
        // machine, or the chord would drop mid-hold.
        XCTAssertTrue(state.isCapsHeld())

        // And the window was not slid: 0.6 s after the REAL press is outside
        // the 0.5 s window, so a deliberate second ⇪4 still fires. Had the
        // synthetic press at 0.4 s re-armed it, this would be 0.2 s in and get
        // swallowed — that is the regression this asserts against.
        XCTAssertEqual(
            state.verdict(type: .keyDown, keyCode: four, at: t0 + 0.6),
            .passWithCapsChord
        )
    }

    /// The marker is what the tap keys off, so round-trip it on a real ⌘4.
    func testPostedHistoryShortcutCarriesTheMarker() {
        guard
            let event = CGEvent(
                keyboardEventSource: CGEventSource(stateID: .hidSystemState),
                virtualKey: CGKeyCode(kVK_ANSI_4),
                keyDown: true
            )
        else { return XCTFail("could not create a CGEvent") }
        XCTAssertFalse(SyntheticEventMarker.isPlumaEvent(event))
        SyntheticEventMarker.mark(event)
        XCTAssertTrue(SyntheticEventMarker.isPlumaEvent(event))

        // Second line of defence: the synthetic ⌘4 carries only Command, never
        // the Caps chord, so Carbon cannot re-trigger the ⇪4 hotkey from it.
        event.flags = .maskCommand
        XCTAssertFalse(event.flags.contains(.maskControl))
        XCTAssertFalse(event.flags.contains(.maskAlternate))
        XCTAssertTrue(event.flags.contains(.maskCommand))
    }

    // MARK: - Constraint 4: an open Spotlight is not toggled closed

    /// The whole point: when Spotlight is already up the plan must omit ⌘Space,
    /// because posting it would close the panel instead of showing history.
    func testAlreadyOpenSpotlightIsNotToggledClosed() {
        let plan = ClipboardHistoryPlan.forSpotlight(
            isOnScreen: StubSpotlight(onScreen: true).isSpotlightOnScreen()
        )
        XCTAssertEqual(plan, .historyOnly)
    }

    func testClosedSpotlightIsOpenedFirst() {
        let plan = ClipboardHistoryPlan.forSpotlight(
            isOnScreen: StubSpotlight(onScreen: false).isSpotlightOnScreen()
        )
        XCTAssertEqual(plan, .openThenHistory)
    }

    // MARK: - The readiness / presence predicate

    /// Captured from `CGWindowListCopyWindowInfo` on macOS 26.7 (25G229) with
    /// Spotlight CLOSED: it owns a 64x64 window at alpha 1.0, an 844x607 at
    /// alpha 1.0, and a 640x56 search field at alpha 0.0.
    ///
    /// Note what this predicate is and is not responsible for: on-screen-ness
    /// is filtered by `kCGWindowListOptionOnScreenOnly` at the call site (with
    /// Spotlight closed, zero of those three windows are in the on-screen
    /// list). This predicate only rejects the wrong windows *within* that list.
    func testPresencePredicateRejectsTheAlwaysPresentDecoyWindows() {
        let pid: pid_t = 4_242

        // The 64x64 window: real alpha, far too small to be the panel. This is
        // why the check is a width threshold and not `kCGWindowLayer == 23` —
        // a window level is exactly the constant an OS update moves.
        XCTAssertFalse(
            SpotlightPresence.matchesSpotlightPanel(
                Self.window(pid: pid, alpha: 1.0, width: 64), pid: pid
            )
        )

        // The search field while closed: panel-width but fully transparent.
        XCTAssertFalse(
            SpotlightPresence.matchesSpotlightPanel(
                Self.window(pid: pid, alpha: 0.0, width: 640), pid: pid
            )
        )

        // Another app's window of exactly the right shape.
        XCTAssertFalse(
            SpotlightPresence.matchesSpotlightPanel(
                Self.window(pid: 9_999, alpha: 1.0, width: 640), pid: pid
            )
        )
    }

    func testPresencePredicateAcceptsTheVisiblePanel() {
        let pid: pid_t = 4_242
        // The 640x56 search field, once shown.
        XCTAssertTrue(
            SpotlightPresence.matchesSpotlightPanel(
                Self.window(pid: pid, alpha: 1.0, width: 640), pid: pid
            )
        )
        // The 844x607 results panel.
        XCTAssertTrue(
            SpotlightPresence.matchesSpotlightPanel(
                Self.window(pid: pid, alpha: 1.0, width: 844), pid: pid
            )
        )
    }

    func testPresencePredicateNeedsBoundsAndAlpha() {
        let pid: pid_t = 4_242
        XCTAssertFalse(
            SpotlightPresence.matchesSpotlightPanel(
                [kCGWindowOwnerPID as String: Int(pid)], pid: pid
            )
        )
    }

    /// The predicate tests above build their dictionaries from Swift-native
    /// `Int`/`Double`, which cast for free. The real dictionary from
    /// `CGWindowListCopyWindowInfo` carries `CFNumber`s. If any of those three
    /// casts ever stops bridging, `matchesSpotlightPanel` returns false for
    /// EVERY window, `isSpotlightOnScreen()` is permanently false, and an
    /// already-open Spotlight gets toggled shut by a ⌘Space it should never
    /// have sent — the exact failure the open-Spotlight rule exists to prevent.
    ///
    /// `testLiveProbeIsFalseWhileSpotlightIsClosed` cannot catch that: a
    /// correct rejection and a total parse failure both read `false`. So pin
    /// the casts to live data instead of to my own dictionaries.
    func testRealWindowDictionariesBridgeToTheTypesThePredicateExpects() throws {
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]]
        let sample = try XCTUnwrap(windows?.first, "no on-screen windows to sample")

        XCTAssertNotNil(
            sample[kCGWindowOwnerPID as String] as? Int,
            "owner PID no longer bridges to Int — the presence probe is now blind"
        )
        XCTAssertNotNil(
            sample[kCGWindowAlpha as String] as? Double,
            "alpha no longer bridges to Double — the presence probe is now blind"
        )
        let bounds = try XCTUnwrap(
            sample[kCGWindowBounds as String] as? [String: Any],
            "window bounds no longer bridge to a dictionary"
        )
        XCTAssertNotNil(
            bounds["Width"] as? Double,
            "bounds width no longer bridges to Double — switch to NSNumber.doubleValue"
        )
    }

    /// And the predicate has to actually accept a real window, not just parse
    /// one. Any on-screen window wider than the threshold, relabelled with the
    /// pid the predicate is asked about, must match — which exercises the live
    /// CFNumber values through the real code path rather than through stubs.
    func testPredicateAcceptsARealWideOnScreenWindow() throws {
        let windows = try XCTUnwrap(
            CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        )
        let wide = try XCTUnwrap(
            windows.first { window in
                guard
                    let bounds = window[kCGWindowBounds as String] as? [String: Any],
                    let width = bounds["Width"] as? Double,
                    let alpha = window[kCGWindowAlpha as String] as? Double
                else { return false }
                return width >= SpotlightPresence.minimumWidth && alpha > 0
            },
            "no wide opaque on-screen window to sample"
        )
        let pid = try XCTUnwrap(wide[kCGWindowOwnerPID as String] as? Int)
        XCTAssertTrue(
            SpotlightPresence.matchesSpotlightPanel(wide, pid: pid_t(pid)),
            "the predicate rejected a real window that meets every criterion"
        )
    }

    /// Spotlight is always resident, so the live probe must be false while it
    /// is closed — otherwise ⌘Space is skipped and a stray ⌘4 lands in
    /// whatever app has focus. This is the measured-safe direction.
    ///
    /// Environmental precondition: Spotlight must not be open while the suite
    /// runs. That is the normal case for a test run and the assertion is worth
    /// the exposure, since this is the only check that exercises the real
    /// `CGWindowListCopyWindowInfo` path end to end.
    func testLiveProbeIsFalseWhileSpotlightIsClosed() {
        XCTAssertNotNil(
            SpotlightPresence.spotlightProcessIdentifier(),
            "com.apple.Spotlight is expected to be resident on macOS 26"
        )
        XCTAssertFalse(SpotlightPresence().isSpotlightOnScreen())
    }

    // MARK: - The chord that gets registered

    /// Would have shipped broken: `CapsLockExpander` ORs ⌃⌥⌘⇧ when the
    /// Caps-chord-with-Shift setting is on, so a constant ⌃⌥⌘4 registration
    /// would never fire and the feature would be silently dead.
    func testRegisteredChordFollowsTheCapsShiftSetting() {
        let base = GlobalShortcut.clipboardHistoryDefault
        XCTAssertEqual(base.keyCode, UInt32(kVK_ANSI_4))
        XCTAssertEqual(base.carbonModifiers, UInt32(controlKey | optionKey | cmdKey))
        XCTAssertTrue(base.isCapsChord)

        let shifted = base.aligningCapsChord(includesShift: true)
        XCTAssertEqual(
            shifted.carbonModifiers,
            UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )
        XCTAssertTrue(shifted.isCapsChord)
        // Both variants are the same physical Caps press.
        XCTAssertTrue(base.conflicts(with: shifted))
    }

    @MainActor
    func testControllerRegistersTheShiftedChordWhenThatSettingIsOn() {
        Preferences.setCapsChordIncludesShift(true, to: defaults)
        let controller = ClipboardHistoryController(
            probe: StubSpotlight(onScreen: false),
            defaults: defaults
        )
        XCTAssertEqual(
            controller.currentShortcut().carbonModifiers,
            UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )

        Preferences.setCapsChordIncludesShift(false, to: defaults)
        XCTAssertEqual(
            controller.currentShortcut().carbonModifiers,
            UInt32(controlKey | optionKey | cmdKey)
        )
        XCTAssertEqual(controller.currentShortcut().keyCode, UInt32(kVK_ANSI_4))
    }

    /// Carbon refuses a duplicate chord, so recording ⇪4 for another feature
    /// would leave one of the two silently dead. It has to be reported.
    func testRecordingCapsFourForAnotherFeatureReportsTheClash() {
        let message = Preferences.conflictMessage(
            for: GlobalShortcut.clipboardHistoryDefault,
            ignoring: .rewrite,
            from: defaults
        )
        XCTAssertEqual(message, "⇪4 is already used by Clipboard History.")
    }

    // MARK: - The test-host guard

    /// `PlumaTests` is a unit-test bundle hosted by the app, so `xcodebuild
    /// test` launches a second pluma next to the one the user is running.
    /// `PlumaApp.init()` is gated on this environment variable so the test host
    /// neither clears the live HID Caps→F18 mapping nor installs a competing
    /// event tap. If Apple ever renames the variable the gate silently opens
    /// again and running the suite would drop the user's Caps Lock key — so the
    /// gate's own premise is asserted here rather than assumed.
    func testTestHostGuardPremiseStillHolds() {
        XCTAssertNotNil(
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"],
            """
            XCTestConfigurationFilePath is missing, so PlumaApp's isRunningTests \
            gate is now false during tests. Fix the gate before running this \
            suite again: as written it will clear the live Caps→F18 remap.
            """
        )
    }

    // MARK: - Helpers

    private struct StubSpotlight: SpotlightPresenceProbing {
        let onScreen: Bool
        func isSpotlightOnScreen() -> Bool { onScreen }
    }

    private static func window(pid: pid_t, alpha: Double, width: Double) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: Int(pid),
            kCGWindowAlpha as String: alpha,
            kCGWindowBounds as String: ["Width": width, "Height": 56.0]
        ]
    }
}
