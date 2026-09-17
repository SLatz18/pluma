import XCTest
@testable import Pluma

// The choice between drawing suggestions into the writer's line and showing them
// on a chip below it. The default matters: inline needs geometry only some apps
// report, and getting it wrong is visible on every keystroke.
final class SuggestionPresentationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "pluma.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // A fresh install gets the chip, because it is the one that works everywhere.
    func testChipIsTheDefault() {
        XCTAssertFalse(Preferences.inlineSuggestions(from: defaults))
    }

    func testInlineCanBeTurnedOnAndOff() {
        Preferences.setInlineSuggestions(true, to: defaults)
        XCTAssertTrue(Preferences.inlineSuggestions(from: defaults))

        Preferences.setInlineSuggestions(false, to: defaults)
        XCTAssertFalse(Preferences.inlineSuggestions(from: defaults))
    }

    // MARK: Who owns the pill

    // Autocomplete offers things nobody asked for; dictation runs because a key
    // is being held. Holding that key used to leave the two racing — a
    // completion would land on top of "Listening…", then the transcript on top
    // of that.
    @MainActor
    func testDictationKeepsThePillWhileAutocompleteTriesToSpeak() {
        let overlay = SuggestionOverlayController()
        overlay.show(
            .suggestion(text: "a suggestion", anchor: CGPoint(x: 100, y: 100)),
            from: .autocomplete
        )
        overlay.show(
            .dictation(transcript: "", anchor: CGPoint(x: 100, y: 100)), from: .dictation
        )
        XCTAssertEqual(overlay.owner, .dictation)

        overlay.show(
            .suggestion(text: "another suggestion", anchor: CGPoint(x: 100, y: 100)),
            from: .autocomplete
        )
        XCTAssertEqual(overlay.owner, .dictation, "autocomplete must not interrupt dictation")
    }

    @MainActor
    func testReaderKeepsThePillWhileAutocompleteTriesToSpeak() {
        let overlay = SuggestionOverlayController()
        overlay.show(
            .status(
                systemImage: "speaker.wave.2.fill",
                message: "Reading…",
                tone: .accent,
                pulses: true,
                anchor: CGPoint(x: 100, y: 100)
            ),
            from: .reader
        )
        overlay.show(
            .suggestion(text: "a suggestion", anchor: CGPoint(x: 100, y: 100)),
            from: .autocomplete
        )
        XCTAssertEqual(overlay.owner, .reader, "autocomplete must not interrupt reader")
    }

    // A deliberate action still yields to the next deliberate action.
    @MainActor
    func testDeliberateOwnersStillPreemptEachOther() {
        let overlay = SuggestionOverlayController()
        overlay.show(
            .dictation(transcript: "", anchor: CGPoint(x: 100, y: 100)), from: .dictation
        )
        overlay.show(
            .status(systemImage: "hand.raised", message: "needs access", anchor: .zero),
            from: .rewrite
        )
        XCTAssertEqual(overlay.owner, .rewrite)
    }

    // Once dictation lets go, ambient suggestions resume.
    @MainActor
    func testAutocompleteResumesAfterDictationReleases() {
        let overlay = SuggestionOverlayController()
        overlay.show(
            .dictation(transcript: "", anchor: CGPoint(x: 100, y: 100)), from: .dictation
        )
        overlay.hide(from: .dictation)
        overlay.show(
            .suggestion(text: "a suggestion", anchor: CGPoint(x: 100, y: 100)),
            from: .autocomplete
        )
        XCTAssertEqual(overlay.owner, .autocomplete)
    }

    func testPillIgnoresSmallVerticalCaretJitter() {
        XCTAssertEqual(
            SuggestionOverlayController.stabilizedPillY(
                proposed: 106,
                previous: 100,
                preserveVertical: false
            ),
            100
        )
    }

    func testPillStillFollowsARealLineChange() {
        XCTAssertEqual(
            SuggestionOverlayController.stabilizedPillY(
                proposed: 120,
                previous: 100,
                preserveVertical: false
            ),
            120
        )
    }

    func testPillKeepsItsVerticalPositionDuringOwnerHandover() {
        XCTAssertEqual(
            SuggestionOverlayController.stabilizedPillY(
                proposed: 140,
                previous: 100,
                preserveVertical: true
            ),
            100
        )
    }

    func testCurrentModelCancellationCanRetry() {
        XCTAssertTrue(
            AutocompleteCoordinator.shouldRetryModelCancellation(
                taskIsCancelled: false,
                sequence: 4,
                currentSequence: 4,
                prefix: "A current sentence",
                currentPrefix: "A current sentence"
            )
        )
    }

    func testTypingOrNewerRequestPreventsModelCancellationRetry() {
        XCTAssertFalse(
            AutocompleteCoordinator.shouldRetryModelCancellation(
                taskIsCancelled: true,
                sequence: 4,
                currentSequence: 4,
                prefix: "A current sentence",
                currentPrefix: "A current sentence"
            )
        )
        XCTAssertFalse(
            AutocompleteCoordinator.shouldRetryModelCancellation(
                taskIsCancelled: false,
                sequence: 4,
                currentSequence: 5,
                prefix: "A current sentence",
                currentPrefix: "A current sentence plus typing"
            )
        )
    }

    func testInFlightCompletionCanRebaseAgainstContinuedTyping() {
        XCTAssertEqual(
            AutocompleteCoordinator.typedSuffix(
                requestPrefix: "Please review",
                currentPrefix: "Please review the "
            ),
            " the "
        )
        XCTAssertTrue(
            AutocompleteCoordinator.shouldRetryModelCancellation(
                taskIsCancelled: false,
                sequence: 4,
                currentSequence: 4,
                prefix: "Please review",
                currentPrefix: "Please review the "
            )
        )
    }

    func testInFlightCompletionRejectsCorrectionsThatDiverge() {
        XCTAssertNil(
            AutocompleteCoordinator.typedSuffix(
                requestPrefix: "Please review",
                currentPrefix: "Please revise"
            )
        )
    }

    func testAcceptedWordKeepsSuggestionOnItsCurrentLine() {
        XCTAssertEqual(
            AutocompleteCoordinator.stabilizedSuggestionY(
                proposed: 140,
                previous: 100,
                preserveVertical: true
            ),
            100
        )
    }

    func testOrdinaryTypingCanStillMoveSuggestionToANewLine() {
        XCTAssertEqual(
            AutocompleteCoordinator.stabilizedSuggestionY(
                proposed: 140,
                previous: 100,
                preserveVertical: false
            ),
            140
        )
    }

    // The chip covers nothing the writer has already put down, so unlike ghost
    // text it has no reason to refuse a caret in the middle of a line. This is
    // the eligibility ghost text still answers no to.
    func testGhostTextStillRefusesMidLineCarets() {
        let precise = CaretGeometry(
            rect: CGRect(x: 40, y: 100, width: 1, height: 17), source: .exactCaret
        )
        let midLine = GhostTextEligibility.of(text: "hello there", caretLocation: 5)
        XCTAssertFalse(midLine.allows(precise))
    }
}

// MARK: - Where status lives

// Status is the app talking about itself, so it may leave the caret for the
// notch. Text the writer is about to accept never does. The geometry is pure so
// it can be checked against hand-built displays without a screen.
final class NotchPlacementTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    // A 14-inch laptop display with a 190 pt notch in a 37 pt menu bar.
    private let laptop = NotchGeometry.Display(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 945),
        notch: CGRect(x: 661, y: 945, width: 190, height: 37)
    )

    // An external monitor to the right of it, with a 25 pt menu bar and no notch.
    private let external = NotchGeometry.Display(
        frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1415),
        notch: nil
    )

    override func setUp() {
        super.setUp()
        suiteName = "pluma.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testStatusNoticesDefaultToTheNotch() {
        XCTAssertEqual(Preferences.statusPlacement(from: defaults), .notch)
    }

    func testStatusPlacementRoundTrips() {
        Preferences.setStatusPlacement(.caret, to: defaults)
        XCTAssertEqual(Preferences.statusPlacement(from: defaults), .caret)
        Preferences.setStatusPlacement(.notch, to: defaults)
        XCTAssertEqual(Preferences.statusPlacement(from: defaults), .notch)
    }

    func testOnlyStatusMovesToTheNotch() {
        let status = OverlayPresentation.Content.status(
            systemImage: "sparkles", message: "Rewriting 2 of 3…", tone: .accent, pulses: false
        )
        XCTAssertTrue(
            OverlayPlacementPolicy.usesNotch(for: status, placement: .notch, companionRunning: false)
        )
        XCTAssertFalse(
            OverlayPlacementPolicy.usesNotch(for: status, placement: .caret, companionRunning: false),
            "the setting keeps status at the caret"
        )
        XCTAssertFalse(
            OverlayPlacementPolicy.usesNotch(for: status, placement: .notch, companionRunning: true),
            "another notch app owns those pixels"
        )
        XCTAssertFalse(
            OverlayPlacementPolicy.usesNotch(
                for: .suggestion(text: "word"), placement: .notch, companionRunning: false
            ),
            "a suggestion is about to be accepted and belongs at the caret"
        )
        XCTAssertFalse(
            OverlayPlacementPolicy.usesNotch(
                for: .dictation(transcript: "live words"), placement: .notch, companionRunning: false
            ),
            "the live transcript stays where the words will land"
        )
    }

    // MARK: Finding the notch

    func testNotchIsTheGapBetweenTheMenuBarAreas() {
        let notch = NotchGeometry.notchRect(
            screenFrame: laptop.frame,
            safeAreaTop: 37,
            auxiliaryTopLeft: CGRect(x: 0, y: 945, width: 661, height: 37),
            auxiliaryTopRight: CGRect(x: 851, y: 945, width: 661, height: 37)
        )
        XCTAssertEqual(notch, CGRect(x: 661, y: 945, width: 190, height: 37))
    }

    func testNoSafeAreaMeansNoNotch() {
        XCTAssertNil(
            NotchGeometry.notchRect(
                screenFrame: external.frame, safeAreaTop: 0,
                auxiliaryTopLeft: nil, auxiliaryTopRight: nil
            )
        )
    }

    func testSafeAreaWithoutAuxiliaryAreasAssumesACentredNotch() {
        let notch = NotchGeometry.notchRect(
            screenFrame: laptop.frame, safeAreaTop: 37,
            auxiliaryTopLeft: nil, auxiliaryTopRight: nil
        )
        XCTAssertEqual(notch?.midX ?? -1, laptop.frame.midX, accuracy: 0.5)
        XCTAssertEqual(notch?.height, 37)
        XCTAssertEqual(notch?.width, DS.Overlay.assumedNotchWidth)
    }

    // MARK: Framing the HUD

    func testHUDIsCentredOnTheNotchAndTopsOutAboveTheScreen() {
        let size = CGSize(width: 320, height: 100)
        let frame = NotchGeometry.panelFrame(for: laptop, size: size)
        XCTAssertEqual(frame.midX, 756, accuracy: 0.5)
        XCTAssertEqual(frame.maxY, laptop.frame.maxY + DS.Overlay.notchHeadroom)
        XCTAssertEqual(frame.size, size)
    }

    func testHUDHidesItsHeadroomAndTheNotch() {
        XCTAssertEqual(NotchGeometry.hiddenTopHeight(for: laptop), DS.Overlay.notchHeadroom + 37)
        XCTAssertEqual(NotchGeometry.hiddenTopHeight(for: external), 0)
    }

    func testHUDFlaresPastTheNotchOnBothSides() {
        XCTAssertEqual(NotchGeometry.minimumWidth(for: laptop), 190 + 2 * DS.Overlay.notchFlare)
        XCTAssertEqual(NotchGeometry.minimumWidth(for: external), 0)
    }

    func testWithoutANotchTheHUDHangsUnderTheMenuBar() {
        let size = CGSize(width: 320, height: 36)
        let frame = NotchGeometry.panelFrame(for: external, size: size)
        XCTAssertEqual(frame.midX, external.visibleFrame.midX, accuracy: 0.5)
        XCTAssertEqual(frame.maxY, external.visibleFrame.maxY - DS.Overlay.screenInset)
        XCTAssertEqual(frame.size, size)
    }

    func testAWideMessageStaysInsideTheDisplay() {
        let frame = NotchGeometry.panelFrame(for: laptop, size: CGSize(width: 1600, height: 100))
        XCTAssertEqual(frame.minX, laptop.frame.minX)
        XCTAssertEqual(frame.width, laptop.frame.width)

        let offCentre = NotchGeometry.Display(
            frame: laptop.frame, visibleFrame: laptop.visibleFrame,
            notch: CGRect(x: 40, y: 945, width: 190, height: 37)
        )
        let nearEdge = NotchGeometry.panelFrame(for: offCentre, size: CGSize(width: 600, height: 100))
        XCTAssertEqual(nearEdge.minX, 0, "slid right rather than falling off the left edge")
    }

    // Tucked, the HUD's bottom edge sits exactly at the notch's bottom edge, so
    // nothing of it shows below the menu bar before it descends.
    func testTheHUDStartsTuckedBehindTheNotch() {
        let target = NotchGeometry.panelFrame(for: laptop, size: CGSize(width: 320, height: 100))
        let tucked = NotchGeometry.tuckedFrame(for: laptop, target: target)
        XCTAssertEqual(tucked.size, target.size)
        XCTAssertEqual(tucked.minY, laptop.notch!.minY, accuracy: 0.5)
    }

    // Hanging free, all of the capsule is visible, so it starts one full height
    // higher — behind the menu bar — and slides down into place.
    func testWithoutANotchTheHUDStartsBehindTheMenuBar() {
        let target = NotchGeometry.panelFrame(for: external, size: CGSize(width: 320, height: 36))
        let tucked = NotchGeometry.tuckedFrame(for: external, target: target)
        XCTAssertEqual(tucked.minY, target.maxY, accuracy: 0.5)
    }

    // The real controller, on a real screen: a status ends up at the notch and
    // hands the panel back to the caret when a suggestion follows.
    @MainActor
    func testStatusPresentsAtTheNotchOnAScreen() throws {
        guard !NSScreen.screens.isEmpty else {
            throw XCTSkip("needs a display")
        }
        let overlay = SuggestionOverlayController()
        overlay.show(
            .status(
                systemImage: "sparkles", message: "Rewriting…", tone: .accent,
                anchor: CGPoint(x: 100, y: 100)
            ),
            from: .rewrite
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(overlay.isShowingAtNotch)

        overlay.hide(from: .rewrite)
        overlay.show(
            .suggestion(text: "a suggestion", anchor: CGPoint(x: 100, y: 100)),
            from: .autocomplete
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertFalse(overlay.isShowingAtNotch)
        overlay.hide()
    }
}
