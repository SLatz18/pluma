import Foundation

/// The smallest surface Reader needs from a synthesizer, so tests can drive
/// speak/stop without `AVSpeechSynthesizer`.
@MainActor
protocol SpeechSpeaking: AnyObject {
    var isSpeaking: Bool { get }
    var onFinish: (() -> Void)? { get set }
    var onFailure: ((String) -> Void)? { get set }
    func speak(_ text: String, voiceIdentifier: String?, rate: Float)
    func stop()
}
