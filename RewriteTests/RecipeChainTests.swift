import XCTest
@testable import Rewrite

@MainActor
final class RecipeChainTests: XCTestCase {

    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "RecipeChainTests.\(name)")!
        defaults.removePersistentDomain(forName: "RecipeChainTests.\(name)")
        return defaults
    }

    // MARK: Persistence

    func testChainRoundTripsInOrder() {
        let defaults = makeDefaults()
        Preferences.saveChain([.grammar, .shorten, .professional], to: defaults)
        XCTAssertEqual(Preferences.chain(from: defaults), [.grammar, .shorten, .professional])
    }

    func testMissingChainSeedsFromLegacyIntentPreference() {
        let defaults = makeDefaults()
        defaults.set(RewriteIntent.professional.rawValue, forKey: Preferences.intentKey)

        XCTAssertEqual(Preferences.chain(from: defaults), [.professional])
        // The seed is written back, so the next read takes the chain path.
        XCTAssertNotNil(defaults.data(forKey: Preferences.chainKey))
    }

    func testPersistedEmptyChainStaysEmpty() {
        let defaults = makeDefaults()
        Preferences.saveChain([], to: defaults)
        XCTAssertEqual(Preferences.chain(from: defaults), [])
    }

    // MARK: Runner

    func testChainRunsStepsInOrderFeedingOutputForward() async throws {
        var calls: [(intent: RewriteIntent, input: String)] = []
        let output = try await RewriteRunner.rewriteChain(
            provider: .appleIntelligence,
            steps: [.grammar, .shorten],
            text: "text",
            ollamaModel: ""
        ) { intent, input in
            calls.append((intent, input))
            return input + "|" + intent.rawValue
        }

        XCTAssertEqual(calls.map(\.intent), [.grammar, .shorten])
        XCTAssertEqual(calls.map(\.input), ["text", "text|grammar"])
        XCTAssertEqual(output, "text|grammar|shorten")
    }

    func testChainReportsProgressAroundEachStep() async throws {
        var events: [ChainProgress] = []
        _ = try await RewriteRunner.rewriteChain(
            provider: .appleIntelligence,
            steps: [.improve, .shorten],
            text: "text",
            ollamaModel: "",
            stepRunner: { _, input in input },
            onProgress: { progress in
                events.append(progress)
            }
        )

        guard events.count == 4 else {
            return XCTFail("expected 4 progress events, got \(events.count)")
        }
        guard
            case .starting(1, 2, .improve) = events[0],
            case .stepFinished(1, 2, _) = events[1],
            case .starting(2, 2, .shorten) = events[2],
            case .stepFinished(2, 2, _) = events[3]
        else {
            return XCTFail("unexpected progress sequence: \(events)")
        }
    }

    func testNonisolatedChainRejectsEmptySteps() async {
        do {
            _ = try await RewriteRunner.rewriteChain(
                provider: .appleIntelligence, steps: [], text: "x", ollamaModel: ""
            )
            XCTFail("expected emptyChain to throw")
        } catch let error as RewriteEngineError {
            guard case .emptyChain = error else {
                return XCTFail("expected emptyChain, got \(error)")
            }
        } catch {
            XCTFail("expected emptyChain, got \(error)")
        }
    }

    func testEmptyChainThrows() async {
        do {
            _ = try await RewriteRunner.rewriteChain(
                provider: .appleIntelligence,
                steps: [],
                text: "text",
                ollamaModel: ""
            ) { _, input in input }
            XCTFail("expected emptyChain to throw")
        } catch let error as RewriteEngineError {
            guard case .emptyChain = error else {
                return XCTFail("expected emptyChain, got \(error)")
            }
        } catch {
            XCTFail("expected emptyChain, got \(error)")
        }
    }

    func testFailingStepStopsTheChain() async {
        struct Boom: Error {}
        var calls = 0
        do {
            _ = try await RewriteRunner.rewriteChain(
                provider: .appleIntelligence,
                steps: [.improve, .shorten, .grammar],
                text: "text",
                ollamaModel: ""
            ) { _, input in
                calls += 1
                if calls == 2 { throw Boom() }
                return input
            }
            XCTFail("expected the chain to throw")
        } catch {
            XCTAssertTrue(error is Boom)
        }
        XCTAssertEqual(calls, 2, "steps after the failure must not run")
    }
}
