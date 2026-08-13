import AVFoundation
import Foundation

/// Cloud TTS via OpenAI. Audio stays in memory for the length of playback.
@MainActor
final class OpenAISpeechEngine: NSObject, SpeechSpeaking {
    var onFinish: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onPlaybackStarted: (() -> Void)?

    var voiceID: String = OpenAITTSCatalog.defaultVoiceID
    var modelID: String = OpenAITTSCatalog.defaultModelID

    private var player: AVAudioPlayer?
    private var speakTask: Task<Void, Never>?
    private(set) var isSpeaking = false

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
                let data = try await OpenAITTSClient.synthesize(
                    text: trimmed,
                    voiceID: selectedVoice,
                    modelID: selectedModel,
                    speed: speed
                )
                guard !Task.isCancelled else { return }
                try self.play(data)
            } catch is CancellationError {
                self.isSpeaking = false
            } catch {
                self.isSpeaking = false
                self.player = nil
                let message = error.localizedDescription
                DebugLog.log("openai speech failed: \(message)", at: .quiet)
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
            throw RewriteEngineError.modelUnavailable("Couldn’t start OpenAI speech playback")
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
            let message = error?.localizedDescription ?? "OpenAI speech could not be decoded"
            self.onFailure?(message)
            self.onFinish?()
        }
    }
}
