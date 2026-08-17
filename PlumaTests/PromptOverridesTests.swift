import XCTest
@testable import Pluma

final class PromptOverridesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var previousStore: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "PromptOverridesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        previousStore = PromptOverrides.store
        PromptOverrides.store = defaults
        PromptOverrides.resetAll()
    }

    override func tearDown() {
        PromptOverrides.resetAll()
        PromptOverrides.store = previousStore
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        previousStore = nil
        super.tearDown()
    }

    func testCatalogCoversEveryEditableRecipe() {
        let ids = Set(PromptOverrides.catalog.map(\.id))
        XCTAssertTrue(ids.contains(PromptOverrides.systemRewriteID))
        XCTAssertTrue(ids.contains(PromptOverrides.systemCompletionID))
        XCTAssertTrue(ids.contains(PromptOverrides.systemDraftReplyID))
        XCTAssertTrue(ids.contains(PromptOverrides.systemSpellingID))
        for intent in RewriteIntent.allCases {
            XCTAssertTrue(ids.contains(intent.promptID), intent.title)
        }
        for directive in CompletionDirective.allCases {
            XCTAssertTrue(ids.contains(directive.promptID), directive.title)
        }
        for directive in CleanupDirective.allCases {
            XCTAssertTrue(ids.contains(directive.promptID), directive.title)
        }
        XCTAssertTrue(ids.contains(PromptOverrides.readerSummarizeID))
    }

    func testUntouchedInstallKeepsShippedBytes() {
        XCTAssertEqual(RewriteIntent.improve.directive, RewriteIntent.improve.shippedDirective)
        XCTAssertEqual(
            CompletionDirective.matchTone.promptDirective,
            CompletionDirective.matchTone.shippedPromptDirective
        )
        XCTAssertEqual(
            CleanupDirective.removeFiller.promptDirective,
            CleanupDirective.removeFiller.shippedPromptDirective
        )
        XCTAssertEqual(
            PromptComposer.readerSummaryDirective,
            PromptComposer.shippedReaderSummaryDirective
        )
        XCTAssertEqual(
            PromptComposer.systemInstructions,
            PromptComposer.shippedSystemInstructions
        )
        XCTAssertEqual(
            PromptComposer.completionSystemInstructions,
            PromptComposer.shippedCompletionSystemInstructions
        )
        XCTAssertEqual(
            PromptComposer.draftReplySystemInstructions,
            PromptComposer.shippedDraftReplySystemInstructions
        )
        XCTAssertEqual(
            PromptComposer.spellingCorrectionInstructions,
            PromptComposer.shippedSpellingCorrectionInstructions
        )
        XCTAssertFalse(PromptOverrides.hasAnyOverride())
    }

    func testSystemOverrideRoundTripsAndResets() {
        PromptOverrides.set(
            "You edit with extreme brevity.",
            for: PromptOverrides.systemRewriteID,
            default: PromptComposer.shippedSystemInstructions
        )
        XCTAssertEqual(
            PromptComposer.systemInstructions,
            "You edit with extreme brevity."
        )
        PromptOverrides.reset(PromptOverrides.systemRewriteID)
        XCTAssertEqual(
            PromptComposer.systemInstructions,
            PromptComposer.shippedSystemInstructions
        )
    }

    func testOverrideRoundTripsAndResets() {
        let intent = RewriteIntent.shorten
        PromptOverrides.set(
            "Make it half as long.",
            for: intent.promptID,
            default: intent.shippedDirective
        )
        XCTAssertEqual(intent.directive, "Make it half as long.")
        XCTAssertTrue(PromptOverrides.isCustom(intent.promptID, default: intent.shippedDirective))

        PromptOverrides.reset(intent.promptID)
        XCTAssertEqual(intent.directive, intent.shippedDirective)
        XCTAssertFalse(PromptOverrides.hasAnyOverride())
    }

    func testIdenticalToShippedIsNotStored() {
        let intent = RewriteIntent.improve
        PromptOverrides.set(
            intent.shippedDirective,
            for: intent.promptID,
            default: intent.shippedDirective
        )
        XCTAssertFalse(PromptOverrides.hasAnyOverride())
        XCTAssertEqual(intent.directive, intent.shippedDirective)
    }

    func testEmptyOverrideFallsBackToShipped() {
        let intent = RewriteIntent.professional
        PromptOverrides.set("   ", for: intent.promptID, default: intent.shippedDirective)
        XCTAssertEqual(intent.directive, intent.shippedDirective)
        XCTAssertFalse(PromptOverrides.hasAnyOverride())
    }

    func testDefaultCompletionChainUsesOverrideWhenCustomized() {
        let baseline = PromptComposer.completionInstructions(
            directives: CompletionDirective.defaultChain
        )
        XCTAssertEqual(baseline, PromptComposer.completionSystemInstructions)

        PromptOverrides.set(
            "Always whisper.",
            for: CompletionDirective.matchTone.promptID,
            default: CompletionDirective.matchTone.shippedPromptDirective
        )
        let customized = PromptComposer.completionInstructions(
            directives: CompletionDirective.defaultChain
        )
        XCTAssertNotEqual(customized, baseline)
        XCTAssertTrue(customized.contains("Always whisper."))
    }

    func testDefaultCleanupChainUsesOverrideWhenCustomized() {
        let transcript = "hello there"
        let baseline = PromptComposer.dictationDirective(
            for: transcript,
            directives: CleanupDirective.defaultChain
        )
        XCTAssertEqual(
            baseline,
            PromptComposer.dictationDirective(for: transcript)
        )

        PromptOverrides.set(
            "Drop every um carefully.",
            for: CleanupDirective.removeFiller.promptID,
            default: CleanupDirective.removeFiller.shippedPromptDirective
        )
        let customized = PromptComposer.dictationDirective(
            for: transcript,
            directives: CleanupDirective.defaultChain
        )
        XCTAssertNotEqual(customized, baseline)
        XCTAssertTrue(customized.contains("Drop every um carefully."))
        XCTAssertTrue(customized.contains(PromptComposer.dictationCleanupBase))
    }

    func testResetAllClearsEveryOverride() {
        PromptOverrides.set(
            "Custom improve",
            for: RewriteIntent.improve.promptID,
            default: RewriteIntent.improve.shippedDirective
        )
        PromptOverrides.set(
            "Custom summarize",
            for: PromptOverrides.readerSummarizeID,
            default: PromptComposer.shippedReaderSummaryDirective
        )
        XCTAssertTrue(PromptOverrides.hasAnyOverride())

        PromptOverrides.resetAll()
        XCTAssertFalse(PromptOverrides.hasAnyOverride())
        XCTAssertEqual(
            PromptComposer.readerSummaryDirective,
            PromptComposer.shippedReaderSummaryDirective
        )
    }
}
