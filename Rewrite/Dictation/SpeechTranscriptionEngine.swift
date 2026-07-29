import AVFoundation
import Foundation
import Speech

enum SpeechTranscriptionError: LocalizedError {
    case localeNotSupported
    case noCompatibleAudioFormat
    case notReady

    var errorDescription: String? {
        switch self {
        case .localeNotSupported: "Dictation does not support this language yet"
        case .noCompatibleAudioFormat: "No compatible audio format for dictation"
        case .notReady: "The speech model is not ready yet"
        }
    }
}

@MainActor
final class SpeechTranscriptionEngine: DictationTranscribing {
    private(set) var availability: TranscriptionAvailability = .checking {
        didSet {
            guard availability != oldValue else { return }
            onAvailabilityChange?(availability)
        }
    }

    var onAvailabilityChange: ((TranscriptionAvailability) -> Void)?
    var onVolatileText: ((String) -> Void)?

    private let requestedLocale: Locale
    private var resolvedLocale: Locale?
    private var analyzer: SpeechAnalyzer?
    private var capture: AudioCaptureSession?
    private var resultsTask: Task<Void, Never>?
    private var finalText = ""

    init(locale: Locale = .current) {
        requestedLocale = locale
    }

    // Downloads the on-device model if this Mac does not have it yet. Safe to
    // call repeatedly; only the first call does work.
    func prepare() async {
        if case .ready = availability { return }

        guard SpeechTranscriber.isAvailable else {
            availability = .unsupported("Dictation is not available on this Mac")
            return
        }
        guard
            let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale)
        else {
            availability = .unsupported(SpeechTranscriptionError.localeNotSupported.localizedDescription)
            return
        }
        resolvedLocale = locale

        let module = makeTranscriber(locale: locale)
        switch await AssetInventory.status(forModules: [module]) {
        case .installed:
            availability = .ready
        case .supported, .downloading:
            availability = .preparing
            do {
                try await AssetInventory.reserve(locale: locale)
                if let request = try await AssetInventory.assetInstallationRequest(
                    supporting: [module]
                ) {
                    try await request.downloadAndInstall()
                }
                availability = .ready
            } catch {
                DebugLog.log("speech model install failed: \(error.localizedDescription)", at: .quiet)
                availability = .unsupported("The speech model could not be downloaded")
            }
        case .unsupported:
            availability = .unsupported(
                SpeechTranscriptionError.localeNotSupported.localizedDescription
            )
        @unknown default:
            availability = .unsupported("Dictation is not available on this Mac")
        }
    }

    // `contextStrings` is resolved after the microphone is already live. Screen
    // OCR costs a few hundred milliseconds, and the input stream buffers, so
    // opening the mic first means no speech is lost while the bias terms are
    // still being gathered — and the analyzer still sees them from the very
    // first sample it consumes.
    func start(contextStrings: @Sendable () async -> [String]) async throws {
        guard case .ready = availability, let locale = resolvedLocale else {
            throw SpeechTranscriptionError.notReady
        }

        finalText = ""
        let transcriber = makeTranscriber(locale: locale)

        guard
            let format = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber]
            )
        else {
            throw SpeechTranscriptionError.noCompatibleAudioFormat
        }

        let capture = AudioCaptureSession(targetFormat: format)
        self.capture = capture
        let stream = try capture.start()

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        let terms = await contextStrings()
        if !terms.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = terms
            try? await analyzer.setContext(context)
            DebugLog.log("dictation bias terms: \(terms.count)")
        }

        try await analyzer.start(inputSequence: stream.map { AnalyzerInput(buffer: $0.buffer) })

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    await MainActor.run {
                        self?.handle(text: text, isFinal: result.isFinal)
                    }
                }
            } catch {
                DebugLog.log("dictation results failed: \(error.localizedDescription)", at: .quiet)
            }
        }
    }

    // Ends the session and returns everything that was finalized.
    func finish() async -> String {
        capture?.stop()
        capture = nil

        if let analyzer {
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                DebugLog.log("dictation finalize failed: \(error.localizedDescription)", at: .quiet)
            }
        }
        await resultsTask?.value
        resultsTask = nil
        analyzer = nil

        return DictationTranscript.assemble(finalText)
    }

    func cancel() async {
        capture?.stop()
        capture = nil
        resultsTask?.cancel()
        resultsTask = nil
        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        analyzer = nil
        finalText = ""
    }

    private func handle(text: String, isFinal: Bool) {
        if isFinal {
            finalText += text
            onVolatileText?(DictationTranscript.assemble(finalText))
        } else {
            onVolatileText?(DictationTranscript.assemble(finalText + text))
        }
    }

    private func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
    }
}
