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
    func testPlaygroundSpeaksWithoutEnablingTheHotkey() {
        let speech = FakeSpeechEngine()
        let controller = ReaderController(
            defaults: defaults,
            overlay: SuggestionOverlayController(),
            speech: speech,
            textProvider: StubTextProvider(source: .empty)
        )
        XCTAssertFalse(controller.isEnabled)

        controller.speakPlaygroundText("playground passage")

        XCTAssertEqual(speech.spoken.map(\.text), ["playground passage"])
        XCTAssertEqual(controller.activity, .reading)
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
