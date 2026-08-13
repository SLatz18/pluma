import XCTest
@testable import Pluma

/// Persistence for the Autocomplete and Dictation builder chains, mirroring
/// the rewrite-chain coverage in RecipeChainTests.
final class DirectiveChainTests: XCTestCase {

    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "DirectiveChainTests.\(name)")!
        defaults.removePersistentDomain(forName: "DirectiveChainTests.\(name)")
        return defaults
    }

    // MARK: Completion chain

    func testCompletionChainRoundTripsInOrder() {
        let defaults = makeDefaults()
        Preferences.saveCompletionChain([.avoidCliches, .matchTone, .fullSentences], to: defaults)
        XCTAssertEqual(
            Preferences.completionChain(from: defaults),
            [.avoidCliches, .matchTone, .fullSentences]
        )
    }

    func testMissingCompletionChainReadsAsDefault() {
        let defaults = makeDefaults()
        XCTAssertEqual(
            Preferences.completionChain(from: defaults),
            CompletionDirective.defaultChain
        )
    }

    func testPersistedEmptyCompletionChainStaysEmpty() {
        let defaults = makeDefaults()
        Preferences.saveCompletionChain([], to: defaults)
        XCTAssertEqual(Preferences.completionChain(from: defaults), [])
    }

    func testUnknownCompletionRawValuesAreDropped() throws {
        let defaults = makeDefaults()
        let data = try JSONEncoder().encode(["matchTone", "notARealCard"])
        defaults.set(data, forKey: Preferences.completionChainKey)
        XCTAssertEqual(Preferences.completionChain(from: defaults), [.matchTone])
    }

    // MARK: Cleanup chain

    func testCleanupChainRoundTripsInOrder() {
        let defaults = makeDefaults()
        Preferences.saveCleanupChain([.bulletPoints, .fixGrammar], to: defaults)
        XCTAssertEqual(
            Preferences.cleanupChain(from: defaults),
            [.bulletPoints, .fixGrammar]
        )
    }

    func testMissingCleanupChainReadsAsDefault() {
        let defaults = makeDefaults()
        XCTAssertEqual(
            Preferences.cleanupChain(from: defaults),
            CleanupDirective.defaultChain
        )
    }

    func testPersistedEmptyCleanupChainStaysEmpty() {
        let defaults = makeDefaults()
        Preferences.saveCleanupChain([], to: defaults)
        XCTAssertEqual(Preferences.cleanupChain(from: defaults), [])
    }

    // Defaults reproduce today's shipped prompts, so an untouched install
    // behaves identically before and after the builders exist.
    func testDefaultChainsReproduceLegacyPrompts() {
        let defaults = makeDefaults()

        XCTAssertEqual(
            PromptComposer.completionInstructions(
                directives: Preferences.completionChain(from: defaults)
            ),
            PromptComposer.completionSystemInstructions
        )
        XCTAssertEqual(
            PromptComposer.dictationDirective(
                for: "hello there",
                directives: Preferences.cleanupChain(from: defaults)
            ),
            PromptComposer.dictationDirective(for: "hello there")
        )
    }
}
