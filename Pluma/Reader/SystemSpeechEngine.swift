import AVFoundation
import Foundation

/// On-device speech. Nothing is written to disk; the utterance lives in memory
/// for the length of the reading.
@MainActor
final class SystemSpeechEngine: NSObject, SpeechSpeaking {
    private let synthesizer = AVSpeechSynthesizer()
    var onFinish: (() -> Void)?
    // On-device synthesis reports no failures; present so the controller can
    // wire failures through the protocol without downcasting.
    var onFailure: ((String) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }

    func speak(_ text: String, voiceIdentifier: String?, rate: Float) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        if let voiceIdentifier, !voiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        }
        utterance.rate = rate
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

extension SystemSpeechEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.onFinish?()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.onFinish?()
        }
    }
}
