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
