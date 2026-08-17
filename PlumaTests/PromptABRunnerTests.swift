import XCTest
@testable import Pluma

@MainActor
final class PromptABRunnerTests: XCTestCase {
    private final class SpyEngine: AIRequestSpying {
        var rewriteCalls: [(system: String, prompt: String)] = []

        func completionRequested(instructions: String, prompt: String) async throws -> String {
            XCTFail("unexpected completion")
            return ""
        }

        func cleanupRequested(directive: String, transcript: String) async throws -> String {
            XCTFail("unexpected cleanup")
            return ""
        }

        func rewriteRequested(system: String, prompt: String) async throws -> String {
            rewriteCalls.append((system, prompt))
            return "rewritten \(rewriteCalls.count)"
        }
    }

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var previousStore: UserDefaults!
    private var spy: SpyEngine!

    override func setUp() async throws {
        suiteName = "PromptABRunnerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        previousStore = PromptOverrides.store
        PromptOverrides.store = defaults
        PromptOverrides.resetAll()
        spy = SpyEngine()
        RewriteRunner.requestSpy = spy
    }

    override func tearDown() async throws {
        RewriteRunner.requestSpy = nil
        spy = nil
        PromptOverrides.resetAll()
        PromptOverrides.store = previousStore
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        previousStore = nil
    }

    func testDirectiveArmsProduceDistinctComposedPrompts() async {
        let fixture = "hello world fixture"
        let armA = "Make it shorter."
        let armB = "Make it more formal."
        let runner = PromptABRunner()

        await runner.run(
            fixture: fixture,
            mode: .directive,
            intent: .improve,
            armA: armA,
            armB: armB,
            provider: .appleIntelligence,
            ollamaModel: ""
        )

        XCTAssertEqual(runner.phase, .done)
        XCTAssertEqual(spy.rewriteCalls.count, 2)

        let composedA = PromptABRunner.composed(
            mode: .directive, intent: .improve, armText: armA, fixture: fixture
        )
        let composedB = PromptABRunner.composed(
            mode: .directive, intent: .improve, armText: armB, fixture: fixture
        )
        XCTAssertNotEqual(composedA.user, composedB.user)
        XCTAssertTrue(composedA.user.contains(armA))
        XCTAssertTrue(composedB.user.contains(armB))
        XCTAssertTrue(composedA.user.contains(fixture))
        XCTAssertFalse(composedA.system.contains(fixture))
        XCTAssertEqual(spy.rewriteCalls[0].prompt, composedA.user)
        XCTAssertEqual(spy.rewriteCalls[1].prompt, composedB.user)
        XCTAssertEqual(runner.resultA?.output, "rewritten 1")
        XCTAssertEqual(runner.resultB?.output, "rewritten 2")
    }

    func testSystemArmsTemporarilyOverrideAndRestore() async {
        let fixture = "source text"
        let customSystem = "You are a terse editor. Return only the edit."
        let runner = PromptABRunner()

        await runner.run(
            fixture: fixture,
            mode: .system,
            intent: .grammar,
            armA: PromptComposer.shippedSystemInstructions,
            armB: customSystem,
            provider: .appleIntelligence,
            ollamaModel: ""
        )

        XCTAssertEqual(runner.phase, .done)
        XCTAssertEqual(spy.rewriteCalls.count, 2)
        XCTAssertEqual(spy.rewriteCalls[0].system, PromptComposer.shippedSystemInstructions)
        XCTAssertEqual(spy.rewriteCalls[1].system, customSystem)
        XCTAssertTrue(spy.rewriteCalls[0].prompt.contains(fixture))
        XCTAssertFalse(spy.rewriteCalls[1].system.contains(fixture))
        // Experiment must leave the live override store clean.
        XCTAssertFalse(PromptOverrides.hasAnyOverride())
        XCTAssertEqual(
            PromptComposer.systemInstructions,
            PromptComposer.shippedSystemInstructions
        )
    }

    func testPromoteDirectiveWritesOverride() {
        let runner = PromptABRunner()
        let winner = "Prefer short Anglo-Saxon words."
        runner.promote(
            label: "B",
            mode: .directive,
            intent: .improve,
            armA: RewriteIntent.improve.shippedDirective,
            armB: winner
        )
        XCTAssertEqual(RewriteIntent.improve.directive, winner)
        XCTAssertTrue(
            PromptOverrides.isCustom(
                RewriteIntent.improve.promptID,
                default: RewriteIntent.improve.shippedDirective
            )
        )
    }

    func testPromoteSystemWritesOverride() {
        let runner = PromptABRunner()
        let winner = "Edit ruthlessly. No filler."
        runner.promote(
            label: "A",
            mode: .system,
            intent: .improve,
            armA: winner,
            armB: PromptComposer.shippedSystemInstructions
        )
        XCTAssertEqual(PromptComposer.systemInstructions, winner)
        XCTAssertTrue(
            PromptOverrides.isCustom(
                PromptOverrides.systemRewriteID,
                default: PromptComposer.shippedSystemInstructions
            )
        )
    }
}
