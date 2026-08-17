import XCTest
@testable import Pluma

/// Proves stacked directive cards survive the whole journey from UI state to
/// the actual provider request — not just prompt composition in isolation.
/// A spy installed on RewriteRunner captures the exact composed instructions
/// the engines would send, so a regression that drops the chain between the
/// coordinator/controller and the request fails here, without manual testing.
@MainActor
final class StackedChainRequestTests: XCTestCase {

    private final class SpyEngine: AIRequestSpying {
        var completionInstructions: String?
        var completionPrompt: String?
        var cleanupDirective: String?
        var cleanupTranscript: String?
        var rewriteSystem: String?
        var rewritePrompt: String?

        func completionRequested(instructions: String, prompt: String) async throws -> String {
            completionInstructions = instructions
            completionPrompt = prompt
            return "spy completion"
        }

        func cleanupRequested(directive: String, transcript: String) async throws -> String {
            cleanupDirective = directive
            cleanupTranscript = transcript
            return "spy cleanup"
        }

        func rewriteRequested(system: String, prompt: String) async throws -> String {
            rewriteSystem = system
            rewritePrompt = prompt
            return "spy rewrite"
        }
    }

    // A transcription engine that never touches the microphone; the dictation
    // test only exercises the cleanup path.
    private final class StubTranscriptionEngine: DictationTranscribing {
        var availability: TranscriptionAvailability = .ready
        var onAvailabilityChange: ((TranscriptionAvailability) -> Void)?
        var onVolatileText: ((String) -> Void)?

        func prepare() async {}
        func start(contextStrings: @Sendable () async -> [String]) async throws {}
        func finish() async -> String { "" }
        func cancel() async {}
    }

    private var spy: SpyEngine!

    override func setUp() {
        super.setUp()
        spy = SpyEngine()
        RewriteRunner.requestSpy = spy
    }

    override func tearDown() {
        RewriteRunner.requestSpy = nil
        spy = nil
        super.tearDown()
    }

    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "StackedChainRequestTests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: Autocomplete: stacked cards reach the completion request

    func testStackedCompletionChainReachesTheRequest() async throws {
        let defaults = makeDefaults()
        defaults.set(false, forKey: Preferences.autocompleteEnabledKey)
        Preferences.saveCompletionChain([.shortCompletions, .fullSentences], to: defaults)

        let coordinator = AutocompleteCoordinator(defaults: defaults)
        XCTAssertEqual(coordinator.directiveChain, [.shortCompletions, .fullSentences])

        let output = try await coordinator.generateCompletion(
            provider: .appleIntelligence,
            context: "The meeting is scheduled for",
            surrounding: nil,
            conversation: nil,
            memory: nil,
            styleProfile: nil,
            ollamaModel: "llama3",
            sequence: 0,
            prefix: "The meeting is scheduled for"
        )

        XCTAssertEqual(output, "spy completion")
        let instructions = try XCTUnwrap(spy.completionInstructions)

        // The request carries the coordinator's own chain, byte for byte.
        XCTAssertEqual(
            instructions,
            PromptComposer.completionInstructions(
                styleProfile: nil,
                directives: [.shortCompletions, .fullSentences]
            )
        )

        // Both stacked cards appear, in tap order.
        let short = try XCTUnwrap(
            instructions.range(of: CompletionDirective.shortCompletions.promptDirective)
        )
        let full = try XCTUnwrap(
            instructions.range(of: CompletionDirective.fullSentences.promptDirective)
        )
        XCTAssertLessThan(short.lowerBound, full.lowerBound)

        let prompt = try XCTUnwrap(spy.completionPrompt)
        XCTAssertTrue(prompt.contains("The meeting is scheduled for"))
    }

    // MARK: Dictation: stacked cards reach the cleanup request

    func testStackedCleanupChainReachesTheRequest() async throws {
        let defaults = makeDefaults()
        defaults.set(false, forKey: Preferences.dictationEnabledKey)
        defaults.set(true, forKey: Preferences.dictationCleanupEnabledKey)
        Preferences.saveCleanupChain([.removeFiller, .bulletPoints], to: defaults)

        let controller = DictationController(
            defaults: defaults, engine: StubTranscriptionEngine()
        )
        XCTAssertEqual(controller.cleanupChain, [.removeFiller, .bulletPoints])

        let transcript = "um so first we ship the beta and uh then we gather feedback"
        let output = await controller.cleanedOutput(for: transcript)

        XCTAssertEqual(output, "spy cleanup")
        XCTAssertEqual(spy.cleanupTranscript, transcript)
        let directive = try XCTUnwrap(spy.cleanupDirective)

        // The request carries the controller's own chain, byte for byte.
        XCTAssertEqual(
            directive,
            PromptComposer.dictationDirective(
                for: transcript, directives: [.removeFiller, .bulletPoints]
            )
        )

        // Both stacked cards appear, in tap order.
        let filler = try XCTUnwrap(
            directive.range(of: CleanupDirective.removeFiller.promptDirective)
        )
        let bullets = try XCTUnwrap(
            directive.range(of: CleanupDirective.bulletPoints.promptDirective)
        )
        XCTAssertLessThan(filler.lowerBound, bullets.lowerBound)
    }

    // MARK: Cleanup off means no request at all

    func testCleanupDisabledNeverIssuesARequest() async {
        let defaults = makeDefaults()
        defaults.set(false, forKey: Preferences.dictationEnabledKey)
        defaults.set(false, forKey: Preferences.dictationCleanupEnabledKey)

        let controller = DictationController(
            defaults: defaults, engine: StubTranscriptionEngine()
        )

        let transcript = "um so first we ship the beta and uh then we gather feedback"
        let output = await controller.cleanedOutput(for: transcript)

        XCTAssertEqual(output, transcript)
        XCTAssertNil(spy.cleanupDirective)
    }
}
