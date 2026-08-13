import XCTest
@testable import Pluma

final class ReaderControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ReaderControllerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Preferences

    func testReaderIsOffByDefault() {
        XCTAssertFalse(Preferences.readerEnabled(from: defaults))
    }

    func testReaderShortcutDefaultsToCapsLockL() {
        XCTAssertEqual(Preferences.readerShortcut(from: defaults), .readerDefault)
        XCTAssertEqual(Preferences.readerShortcut(from: defaults).display, "⇪L")
    }

    func testReaderShortcutRoundTrips() {
        let custom = GlobalShortcut(keyCode: 40, carbonModifiers: 4096, display: "⌃K")
        Preferences.saveReaderShortcut(custom, to: defaults)
        XCTAssertEqual(Preferences.readerShortcut(from: defaults), custom)
        XCTAssertEqual(Preferences.globalShortcut(from: defaults), .default)
        XCTAssertEqual(Preferences.dictationShortcut(from: defaults), .dictationDefault)
        XCTAssertEqual(Preferences.clipboardShortcut(from: defaults), .clipboardDefault)
    }

    func testReaderRateDefaultsAndClamps() {
        XCTAssertEqual(Preferences.readerRate(from: defaults), Preferences.defaultReaderRate)
        Preferences.setReaderRate(0.1, to: defaults)
        XCTAssertEqual(Preferences.readerRate(from: defaults), Preferences.readerRateRange.lowerBound)
        Preferences.setReaderRate(0.9, to: defaults)
        XCTAssertEqual(Preferences.readerRate(from: defaults), Preferences.readerRateRange.upperBound)
    }

    func testReaderVoiceIdentifierRoundTrips() {
        XCTAssertEqual(Preferences.readerVoiceIdentifier(from: defaults), "")
        Preferences.setReaderVoiceIdentifier("com.apple.voice.test", to: defaults)
        XCTAssertEqual(Preferences.readerVoiceIdentifier(from: defaults), "com.apple.voice.test")
    }

    func testReaderDeliveryModeDefaultsToVerbatimAndRoundTrips() {
        XCTAssertEqual(Preferences.readerDeliveryMode(from: defaults), .verbatim)
        Preferences.setReaderDeliveryMode(.summarizeWhenHelpful, to: defaults)
        XCTAssertEqual(Preferences.readerDeliveryMode(from: defaults), .summarizeWhenHelpful)
    }

    func testReaderSpeechProviderDefaultsToAppleAndRoundTrips() {
        XCTAssertEqual(Preferences.readerSpeechProvider(from: defaults), .appleOnDevice)
        Preferences.setReaderSpeechProvider(.openAI, to: defaults)
        XCTAssertEqual(Preferences.readerSpeechProvider(from: defaults), .openAI)
    }

    func testOpenAITTSVoiceAndModelRoundTrip() {
        XCTAssertEqual(Preferences.openAITTSVoice(from: defaults), .nova)
        Preferences.setOpenAITTSVoice(.onyx, to: defaults)
        XCTAssertEqual(Preferences.openAITTSVoice(from: defaults), .onyx)

        XCTAssertEqual(Preferences.openAITTSModel(from: defaults), .tts1HD)
        Preferences.setOpenAITTSModel(.gpt4oMiniTTS, to: defaults)
        XCTAssertEqual(Preferences.openAITTSModel(from: defaults), .gpt4oMiniTTS)
    }

    func testReaderDeliveryModesProvideBuilderCopyAndSymbols() {
        for mode in ReaderDeliveryMode.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.shortDescription.isEmpty)
            XCTAssertFalse(mode.symbolName.isEmpty)
        }
    }

    func testReaderSummaryDirectivePreservesImportantSpokenDetails() {
        let directive = PromptComposer.readerSummaryDirective.lowercased()
        for detail in ["names", "numbers", "dates", "deadlines", "decisions", "action items"] {
            XCTAssertTrue(directive.contains(detail), "missing \(detail)")
        }
        XCTAssertTrue(directive.contains("short and clear"))
    }

    // MARK: - Text source

    func testSelectionWinsOverClipboard() {
        let source = ReaderTextSource.resolve(
            isSecureField: false,
            selectedText: "from the field",
            clipboardText: "from the clipboard"
        )
        XCTAssertEqual(source, .selection("from the field"))
    }

    func testWhitespaceSelectionFallsThroughToClipboard() {
        let source = ReaderTextSource.resolve(
            isSecureField: false,
            selectedText: " \n\t ",
            clipboardText: "copied"
        )
        XCTAssertEqual(source, .clipboard("copied"))
    }

    func testEmptySelectionAndClipboardIsEmpty() {
        let source = ReaderTextSource.resolve(
            isSecureField: false,
            selectedText: nil,
            clipboardText: nil
        )
        XCTAssertEqual(source, .empty)
    }

    func testSecureFieldRefusesSelectionAndClipboard() {
        let source = ReaderTextSource.resolve(
            isSecureField: true,
            selectedText: "secret",
            clipboardText: "also secret"
        )
        XCTAssertEqual(source, .secureField)
        XCTAssertNil(source.spokenText)
    }

    @MainActor
    func testLiveProviderCopiesSelectionWhenAccessibilityCannotExposeIt() async {
        let copier = StubReaderSelectionCopier(result: "selected in Google Docs")
        let provider = LiveReaderTextProvider(
            focusReader: StubReaderFocusReader(
                snapshot: ReaderFocusSnapshot(
                    isAccessibilityTrusted: true,
                    isSecureField: false,
                    selectedText: nil
                )
            ),
            selectionCopier: copier
        )

        let source = await provider.currentSource()
        XCTAssertEqual(source, .selection("selected in Google Docs"))
        XCTAssertEqual(copier.copyCount, 1)
    }

    @MainActor
    func testLiveProviderDoesNotReadStaleClipboardWithoutAccessibility() async {
        let copier = StubReaderSelectionCopier(result: "stale clipboard text")
        let provider = LiveReaderTextProvider(
            focusReader: StubReaderFocusReader(
                snapshot: ReaderFocusSnapshot(
                    isAccessibilityTrusted: false,
                    isSecureField: false,
                    selectedText: nil
                )
            ),
            selectionCopier: copier
        )

        let source = await provider.currentSource()
        XCTAssertEqual(source, .accessibilityDenied)
        XCTAssertEqual(copier.copyCount, 0)
    }

    @MainActor
    func testLiveProviderDoesNotCopyFromSecureField() async {
        let copier = StubReaderSelectionCopier(result: "must not be read")
        let provider = LiveReaderTextProvider(
            focusReader: StubReaderFocusReader(
                snapshot: ReaderFocusSnapshot(
                    isAccessibilityTrusted: true,
                    isSecureField: true,
                    selectedText: nil
                )
            ),
            selectionCopier: copier
        )

        let source = await provider.currentSource()
        XCTAssertEqual(source, .secureField)
        XCTAssertEqual(copier.copyCount, 0)
    }

    @MainActor
    func testLiveProviderPrefersNativeSelectionWithoutCopying() async {
        let copier = StubReaderSelectionCopier(result: "copied fallback")
        let provider = LiveReaderTextProvider(
            focusReader: StubReaderFocusReader(
                snapshot: ReaderFocusSnapshot(
                    isAccessibilityTrusted: true,
                    isSecureField: false,
                    selectedText: "native selection"
                )
            ),
            selectionCopier: copier
        )

        let source = await provider.currentSource()
        XCTAssertEqual(source, .selection("native selection"))
        XCTAssertEqual(copier.copyCount, 0)
    }

    // MARK: - Conflicts

    func testDefaultReaderChordDoesNotConflict() {
        XCTAssertNil(ReaderController.conflict(for: .readerDefault, defaults: defaults))
    }

    func testReaderConflictsWithRewriteSelection() {
        let conflict = ReaderController.conflict(for: .default, defaults: defaults)
        XCTAssertNotNil(conflict)
        XCTAssertTrue(conflict?.contains("Rewrite Selection") == true)
    }

    func testReaderConflictsWithDictation() {
        let conflict = ReaderController.conflict(for: .dictationDefault, defaults: defaults)
        XCTAssertNotNil(conflict)
        XCTAssertTrue(conflict?.contains("Dictation") == true)
    }

    func testReaderConflictsWithClipboardRewrite() {
        let conflict = ReaderController.conflict(for: .clipboardDefault, defaults: defaults)
        XCTAssertNotNil(conflict)
        XCTAssertTrue(conflict?.contains("Clipboard Rewrite") == true)
    }

    func testReaderConflictsWithDraftReply() {
        let conflict = ReaderController.conflict(for: .draftReplyDefault, defaults: defaults)
        XCTAssertNotNil(conflict)
        XCTAssertTrue(conflict?.contains("Draft a Reply") == true)
    }

    // MARK: - Controller

    @MainActor
    func testEmptySourceDoesNotSpeak() async {
        let speech = FakeSpeechEngine()
        let provider = StubTextProvider(source: .empty)
        let controller = ReaderController(
            defaults: defaults,
            overlay: SuggestionOverlayController(),
            speech: speech,
            textProvider: provider
        )
        controller.isEnabled = true
        await controller.handlePress()

        XCTAssertTrue(speech.spoken.isEmpty)
        XCTAssertEqual(controller.activity, .idle)
    }

    @MainActor
    func testSecureFieldDoesNotSpeak() async {
        let speech = FakeSpeechEngine()
        let provider = StubTextProvider(source: .secureField)
        let controller = ReaderController(
            defaults: defaults,
            overlay: SuggestionOverlayController(),
            speech: speech,
            textProvider: provider
        )
        controller.isEnabled = true
        await controller.handlePress()

        XCTAssertTrue(speech.spoken.isEmpty)
        XCTAssertEqual(controller.activity, .idle)
    }

    @MainActor
    func testMissingAccessibilityDoesNotSpeakClipboardText() async {
        let speech = FakeSpeechEngine()
        let provider = StubTextProvider(source: .accessibilityDenied)
        let controller = ReaderController(
            defaults: defaults,
            overlay: SuggestionOverlayController(),
            speech: speech,
            textProvider: provider
        )
        controller.isEnabled = true
        await controller.handlePress()

        XCTAssertTrue(speech.spoken.isEmpty)
        XCTAssertEqual(controller.activity, .idle)
    }

    @MainActor
    func testSelectionIsSpoken() async {
        let speech = FakeSpeechEngine()
        let provider = StubTextProvider(source: .selection("hello from the field"))
        let controller = ReaderController(
            defaults: defaults,
            overlay: SuggestionOverlayController(),
            speech: speech,
            textProvider: provider
        )
        controller.isEnabled = true
        await controller.handlePress()

        XCTAssertEqual(speech.spoken.map(\.text), ["hello from the field"])
        XCTAssertEqual(controller.activity, .reading)
        XCTAssertTrue(controller.isSpeaking)
    }

    @MainActor
    func testClipboardFallbackIsSpoken() async {
        let speech = FakeSpeechEngine()
        let provider = StubTextProvider(source: .clipboard("copied words"))
        let controller = ReaderController(
            defaults: defaults,
            overlay: SuggestionOverlayController(),
            speech: speech,
            textProvider: provider
        )
        controller.isEnabled = true
        await controller.handlePress()

        XCTAssertEqual(speech.spoken.map(\.text), ["copied words"])
        XCTAssertEqual(controller.activity, .reading)
    }

    @MainActor
    func testSecondPressStopsReading() async {
        let speech = FakeSpeechEngine()
        let provider = StubTextProvider(source: .selection("a long passage"))
        let controller = ReaderController(
            defaults: defaults,
            overlay: SuggestionOverlayController(),
            speech: speech,
            textProvider: provider
        )
        controller.isEnabled = true
        await controller.handlePress()
        XCTAssertEqual(controller.activity, .reading)

        await controller.handlePress()
        XCTAssertEqual(speech.stopCount, 1)
        XCTAssertEqual(controller.activity, .idle)
        XCTAssertFalse(controller.isSpeaking)
    }

    @MainActor
    func testPlaygroundSpeaksWithoutEnablingTheHotkey() async {
        let speech = FakeSpeechEngine()
        let controller = ReaderController(
            defaults: defaults,
            overlay: SuggestionOverlayController(),
            speech: speech,
            textProvider: StubTextProvider(source: .empty)
        )
        XCTAssertFalse(controller.isEnabled)

        await controller.speakPlaygroundText("playground passage")

        XCTAssertEqual(speech.spoken.map(\.text), ["playground passage"])
        XCTAssertEqual(controller.activity, .reading)
    }

    @MainActor
    func testSummaryModeSpeaksSummarizerOutput() async {
        let speech = FakeSpeechEngine()
        let summarizer = FakeReaderSummarizer(result: .success("Three key points and a Friday deadline."))
        let controller = ReaderController(
            defaults: defaults,
            overlay: SuggestionOverlayController(),
            speech: speech,
            textProvider: StubTextProvider(source: .selection("A much longer source passage.")),
            summarizer: summarizer
        )
        controller.deliveryMode = .summarizeWhenHelpful
        controller.isEnabled = true

        await controller.handlePress()

        XCTAssertEqual(summarizer.inputs, ["A much longer source passage."])
        XCTAssertEqual(speech.spoken.map(\.text), ["Three key points and a Friday deadline."])
        XCTAssertEqual(controller.activity, .reading)
        XCTAssertNil(controller.errorMessage)
    }

    @MainActor
    func testSummaryFailureDoesNotFallBackToReadingSource() async {
        let speech = FakeSpeechEngine()
        let summarizer = FakeReaderSummarizer(
            result: .failure(RewriteEngineError.modelUnavailable("Model unavailable for test."))
        )
        let controller = ReaderController(
            defaults: defaults,
            overlay: SuggestionOverlayController(),
            speech: speech,
            textProvider: StubTextProvider(source: .selection("Do not read this verbatim.")),
            summarizer: summarizer
        )
        controller.deliveryMode = .summarizeWhenHelpful
        controller.isEnabled = true

        await controller.handlePress()

        XCTAssertTrue(speech.spoken.isEmpty)
        XCTAssertEqual(controller.activity, .idle)
        XCTAssertEqual(controller.errorMessage, "Model unavailable for test.")
    }

    @MainActor
    func testSecondPressWhileSummarizingPreventsLaterSpeech() async {
        let speech = FakeSpeechEngine()
        let summarizer = SuspendingReaderSummarizer()
        let controller = ReaderController(
            defaults: defaults,
            overlay: SuggestionOverlayController(),
            speech: speech,
            textProvider: StubTextProvider(source: .selection("A long source.")),
            summarizer: summarizer
        )
        controller.deliveryMode = .summarizeWhenHelpful
        controller.isEnabled = true

        let firstPress = Task { await controller.handlePress() }
        while controller.activity != .processing { await Task.yield() }

        await controller.handlePress()
        XCTAssertEqual(controller.activity, .idle)

        summarizer.resume(returning: "A late summary.")
        await firstPress.value
        XCTAssertTrue(speech.spoken.isEmpty)
    }

    @MainActor
    func testNaturalFinishReturnsToIdle() async {
        let speech = FakeSpeechEngine()
        let controller = ReaderController(
            defaults: defaults,
            overlay: SuggestionOverlayController(),
            speech: speech,
            textProvider: StubTextProvider(source: .selection("done"))
        )
        controller.isEnabled = true
        await controller.handlePress()

        speech.finishNaturally()
        XCTAssertEqual(controller.activity, .idle)
        XCTAssertFalse(controller.isSpeaking)
    }

    @MainActor
    func testDisabledHotkeyDoesNotSpeak() async {
        let speech = FakeSpeechEngine()
        let controller = ReaderController(
            defaults: defaults,
            overlay: SuggestionOverlayController(),
            speech: speech,
            textProvider: StubTextProvider(source: .selection("nope"))
        )
        await controller.handlePress()
        XCTAssertTrue(speech.spoken.isEmpty)
        XCTAssertEqual(controller.activity, .off)
    }

    @MainActor
    func testOpenAISpeechProviderWithoutKeyDoesNotSpeak() async {
        let speech = FakeSpeechEngine()
        let controller = ReaderController(
            defaults: defaults,
            overlay: SuggestionOverlayController(),
            speech: speech,
            textProvider: StubTextProvider(source: .selection("cloud please")),
            openAIKeyPresent: { false }
        )
        controller.isEnabled = true
        controller.speechProvider = .openAI
        await controller.handlePress()
        XCTAssertTrue(speech.spoken.isEmpty)
        XCTAssertEqual(controller.activity, .idle)
    }
}

@MainActor
private final class FakeSpeechEngine: SpeechSpeaking {
    private(set) var spoken: [(text: String, voice: String?, rate: Float)] = []
    private(set) var stopCount = 0
    var isSpeaking = false
    var onFinish: (() -> Void)?

    func speak(_ text: String, voiceIdentifier: String?, rate: Float) {
        spoken.append((text, voiceIdentifier, rate))
        isSpeaking = true
    }

    func stop() {
        stopCount += 1
        isSpeaking = false
    }

    func finishNaturally() {
        isSpeaking = false
        onFinish?()
    }
}

@MainActor
private final class StubTextProvider: ReaderTextProviding {
    var source: ReaderTextSource

    init(source: ReaderTextSource) {
        self.source = source
    }

    func currentSource() async -> ReaderTextSource { source }
}

@MainActor
private struct StubReaderFocusReader: ReaderFocusReading {
    let snapshot: ReaderFocusSnapshot

    func currentSnapshot() -> ReaderFocusSnapshot { snapshot }
}

@MainActor
private final class StubReaderSelectionCopier: ReaderSelectionCopying {
    let result: String?
    private(set) var copyCount = 0

    init(result: String?) {
        self.result = result
    }

    func copySelectedText() async -> String? {
        copyCount += 1
        return result
    }
}

@MainActor
private final class FakeReaderSummarizer: ReaderSummarizing {
    private(set) var inputs: [String] = []
    let result: Result<String, Error>

    init(result: Result<String, Error>) {
        self.result = result
    }

    func summarize(_ text: String) async throws -> String {
        inputs.append(text)
        return try result.get()
    }
}

@MainActor
private final class SuspendingReaderSummarizer: ReaderSummarizing {
    private var continuation: CheckedContinuation<String, Error>?

    func summarize(_ text: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(returning summary: String) {
        continuation?.resume(returning: summary)
        continuation = nil
    }
}
