import AVFoundation
import Foundation
import Speech

// Runs the on-device transcriber over a recording instead of a live microphone,
// which is what lets the comparison hand both transcribers the same audio rather
// than asking the user to say the same sentence twice.
enum AppleFileTranscriber {
    static func transcribe(fileURL: URL, locale: Locale = .current) async throws -> String {
        guard SpeechTranscriber.isAvailable else {
            throw SpeechTranscriptionError.notReady
        }
        guard let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw SpeechTranscriptionError.localeNotSupported
        }

        let transcriber = SpeechTranscriber(
            locale: resolved,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        guard case .installed = await AssetInventory.status(forModules: [transcriber]) else {
            throw SpeechTranscriptionError.notReady
        }

        let file = try AVAudioFile(forReading: fileURL)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // The results stream has to be consumed while the file is being analyzed;
        // starting it afterwards would miss everything already emitted.
        let collector = Task {
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }

        _ = try await analyzer.analyzeSequence(from: file)
        try await analyzer.finalizeAndFinishThroughEndOfInput()

        let text = try await collector.value
        return DictationTranscript.assemble(text)
    }
}
