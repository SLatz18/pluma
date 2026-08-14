import AVFoundation
import Foundation

/// Cloud TTS (OpenAI, or any OpenAI-compatible endpoint via an injected
/// synthesizer). Audio stays in memory for the length of playback.
@MainActor
final class OpenAISpeechEngine: NSObject, SpeechSpeaking {
    typealias Synthesize = @Sendable (
        _ text: String, _ voiceID: String, _ modelID: String, _ speed: Double
    ) async throws -> Data

    var onFinish: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onPlaybackStarted: (() -> Void)?

    var voiceID: String = OpenAITTSCatalog.defaultVoiceID
    var modelID: String = OpenAITTSCatalog.defaultModelID

    private let synthesize: Synthesize
    private var player: AVAudioPlayer?
    private var speakTask: Task<Void, Never>?
    private(set) var isSpeaking = false

    init(synthesize: @escaping Synthesize = { text, voiceID, modelID, speed in
        try await OpenAITTSClient.synthesize(
            text: text, voiceID: voiceID, modelID: modelID, speed: speed
        )
    }) {
        self.synthesize = synthesize
        super.init()
    }

    func speak(_ text: String, voiceIdentifier: String?, rate: Float) {
        stop()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onFinish?()
            return
        }

        isSpeaking = true
        let selectedVoice = voiceID
        let selectedModel = modelID
        let speed = ReaderVoiceCatalog.openAISpeed(fromReaderRate: Double(rate))

        speakTask = Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await self.synthesize(trimmed, selectedVoice, selectedModel, speed)
                guard !Task.isCancelled else {
                    self.isSpeaking = false
                    DebugLog.log("cloud speech cancelled", at: .quiet)
                    return
                }
                try self.play(data)
            } catch is CancellationError {
                self.isSpeaking = false
                DebugLog.log("cloud speech cancelled", at: .quiet)
            } catch {
                self.isSpeaking = false
                self.player = nil
                let message = error.localizedDescription
                DebugLog.log("cloud speech failed: \(message)", at: .quiet)
                self.onFailure?(message)
                self.onFinish?()
            }
        }
    }

    func stop() {
        speakTask?.cancel()
        speakTask = nil
        player?.stop()
        player = nil
        isSpeaking = false
    }

    private func play(_ data: Data) throws {
        let player = try AVAudioPlayer(data: data)
        player.delegate = self
        self.player = player
        guard player.play() else {
            throw RewriteEngineError.modelUnavailable("Couldn’t start speech playback")
        }
        onPlaybackStarted?()
    }
}

extension OpenAISpeechEngine: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isSpeaking = false
            self.player = nil
            self.onFinish?()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isSpeaking = false
            self.player = nil
            let message = error?.localizedDescription ?? "Speech audio could not be decoded"
            self.onFailure?(message)
            self.onFinish?()
        }
    }
}
