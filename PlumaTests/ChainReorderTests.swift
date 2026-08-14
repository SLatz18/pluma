import XCTest
@testable import Pluma

/// Reordering coverage for the three pipeline strips: swapping a step with a
/// neighbor, the no-op edges, unknown items, and that the new order is what
/// Preferences hands back after a quit-and-relaunch.
@MainActor
final class ChainReorderTests: XCTestCase {

    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "ChainReorderTests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // A transcriber that never touches the mic, so DictationController can be
    // built in a test host without audio or speech-model side effects.
    private final class StubTranscriptionEngine: DictationTranscribing {
        var availability: TranscriptionAvailability = .ready
        var onAvailabilityChange: ((TranscriptionAvailability) -> Void)?
        var onVolatileText: ((String) -> Void)?

        func prepare() async {}
        func start(contextStrings: @Sendable () async -> [String]) async throws {}
        func finish() async -> String { "" }
        func cancel() async {}
    }

    // MARK: Rewrite chain

    func testMoveInChainSwapsMiddleItemDown() {
        let defaults = makeDefaults()
        Preferences.saveChain([.grammar, .shorten, .professional], to: defaults)
        let model = RewriteViewModel(defaults: defaults)

        model.moveInChain(.shorten, offset: 1)

        XCTAssertEqual(model.chain, [.grammar, .professional, .shorten])
    }

    func testMoveInChainSwapsMiddleItemUp() {
        let defaults = makeDefaults()
        Preferences.saveChain([.grammar, .shorten, .professional], to: defaults)
        let model = RewriteViewModel(defaults: defaults)

        model.moveInChain(.shorten, offset: -1)

        XCTAssertEqual(model.chain, [.shorten, .grammar, .professional])
    }

    func testMoveInChainIsNoOpAtEitherEnd() {
        let defaults = makeDefaults()
        Preferences.saveChain([.grammar, .shorten, .professional], to: defaults)
        let model = RewriteViewModel(defaults: defaults)

        model.moveInChain(.grammar, offset: -1)
        model.moveInChain(.professional, offset: 1)

        XCTAssertEqual(model.chain, [.grammar, .shorten, .professional])
        XCTAssertEqual(
            Preferences.chain(from: defaults),
            [.grammar, .shorten, .professional]
        )
    }

    func testMoveInChainIgnoresItemNotInChain() {
        let defaults = makeDefaults()
        Preferences.saveChain([.grammar, .shorten], to: defaults)
        let model = RewriteViewModel(defaults: defaults)

        model.moveInChain(.improve, offset: 1)

        XCTAssertEqual(model.chain, [.grammar, .shorten])
    }

    func testMoveInChainPersistsReorderAcrossRelaunch() {
        let defaults = makeDefaults()
        Preferences.saveChain([.grammar, .shorten, .professional], to: defaults)
        let model = RewriteViewModel(defaults: defaults)

        model.moveInChain(.professional, offset: -1)

        // A relaunch is a fresh read of the same defaults.
        XCTAssertEqual(
            Preferences.chain(from: defaults),
            [.grammar, .professional, .shorten]
        )
        let relaunched = RewriteViewModel(defaults: defaults)
        XCTAssertEqual(relaunched.chain, [.grammar, .professional, .shorten])
    }

    // MARK: Completion chain

    func testMoveDirectiveSwapsMiddleItem() {
        let defaults = makeDefaults()
        Preferences.saveCompletionChain(
            [.matchTone, .avoidCliches, .fullSentences], to: defaults
        )
        let coordinator = AutocompleteCoordinator(defaults: defaults)

        coordinator.moveDirective(.avoidCliches, offset: 1)

        XCTAssertEqual(
            coordinator.directiveChain,
            [.matchTone, .fullSentences, .avoidCliches]
        )
    }

    func testMoveDirectiveIsNoOpAtEitherEnd() {
        let defaults = makeDefaults()
        Preferences.saveCompletionChain(
            [.matchTone, .avoidCliches, .fullSentences], to: defaults
        )
        let coordinator = AutocompleteCoordinator(defaults: defaults)

        coordinator.moveDirective(.matchTone, offset: -1)
        coordinator.moveDirective(.fullSentences, offset: 1)

        XCTAssertEqual(
            coordinator.directiveChain,
            [.matchTone, .avoidCliches, .fullSentences]
        )
        XCTAssertEqual(
            Preferences.completionChain(from: defaults),
            [.matchTone, .avoidCliches, .fullSentences]
        )
    }

    func testMoveDirectiveIgnoresItemNotInChain() {
        let defaults = makeDefaults()
        Preferences.saveCompletionChain([.matchTone, .fullSentences], to: defaults)
        let coordinator = AutocompleteCoordinator(defaults: defaults)

        coordinator.moveDirective(.shortCompletions, offset: -1)

        XCTAssertEqual(coordinator.directiveChain, [.matchTone, .fullSentences])
    }

    func testMoveDirectivePersistsReorderAcrossRelaunch() {
        let defaults = makeDefaults()
        Preferences.saveCompletionChain(
            [.matchTone, .avoidCliches, .fullSentences], to: defaults
        )
        let coordinator = AutocompleteCoordinator(defaults: defaults)

        coordinator.moveDirective(.fullSentences, offset: -1)

        XCTAssertEqual(
            Preferences.completionChain(from: defaults),
            [.matchTone, .fullSentences, .avoidCliches]
        )
        let relaunched = AutocompleteCoordinator(defaults: defaults)
        XCTAssertEqual(
            relaunched.directiveChain,
            [.matchTone, .fullSentences, .avoidCliches]
        )
    }

    // MARK: Cleanup chain

    private func makeDictationController(_ defaults: UserDefaults) -> DictationController {
        DictationController(defaults: defaults, engine: StubTranscriptionEngine())
    }

    func testMoveCleanupDirectiveSwapsMiddleItem() {
        let defaults = makeDefaults()
        Preferences.saveCleanupChain(
            [.removeFiller, .fixGrammar, .addPunctuation], to: defaults
        )
        let controller = makeDictationController(defaults)

        controller.moveCleanupDirective(.fixGrammar, offset: 1)

        XCTAssertEqual(
            controller.cleanupChain,
            [.removeFiller, .addPunctuation, .fixGrammar]
        )
    }

    func testMoveCleanupDirectiveIsNoOpAtEitherEnd() {
        let defaults = makeDefaults()
        Preferences.saveCleanupChain(
            [.removeFiller, .fixGrammar, .addPunctuation], to: defaults
        )
        let controller = makeDictationController(defaults)

        controller.moveCleanupDirective(.removeFiller, offset: -1)
        controller.moveCleanupDirective(.addPunctuation, offset: 1)

        XCTAssertEqual(
            controller.cleanupChain,
            [.removeFiller, .fixGrammar, .addPunctuation]
        )
        XCTAssertEqual(
            Preferences.cleanupChain(from: defaults),
            [.removeFiller, .fixGrammar, .addPunctuation]
        )
    }

    func testMoveCleanupDirectiveIgnoresItemNotInChain() {
        let defaults = makeDefaults()
        Preferences.saveCleanupChain([.removeFiller, .fixGrammar], to: defaults)
        let controller = makeDictationController(defaults)

        controller.moveCleanupDirective(.bulletPoints, offset: 1)

        XCTAssertEqual(controller.cleanupChain, [.removeFiller, .fixGrammar])
    }

    func testMoveCleanupDirectivePersistsReorderAcrossRelaunch() {
        let defaults = makeDefaults()
        Preferences.saveCleanupChain(
            [.removeFiller, .fixGrammar, .addPunctuation], to: defaults
        )
        let controller = makeDictationController(defaults)

        controller.moveCleanupDirective(.addPunctuation, offset: -1)

        XCTAssertEqual(
            Preferences.cleanupChain(from: defaults),
            [.removeFiller, .addPunctuation, .fixGrammar]
        )
        let relaunched = makeDictationController(defaults)
        XCTAssertEqual(
            relaunched.cleanupChain,
            [.removeFiller, .addPunctuation, .fixGrammar]
        )
    }
}
