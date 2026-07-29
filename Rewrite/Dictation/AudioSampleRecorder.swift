import AVFoundation
import Foundation

// Records one sample of microphone audio to memory so it can be transcribed more
// than once. Separate from the dictation path, which streams and discards.
@MainActor
final class AudioSampleRecorder {
    private var capture: AudioCaptureSession?
    private var task: Task<Data, Never>?

    private(set) var isRecording = false

    func start() throws {
        guard !isRecording, let format = PCM16Audio.captureFormat else { return }

        let capture = AudioCaptureSession(targetFormat: format)
        self.capture = capture
        let stream = try capture.start()
        isRecording = true

        task = Task {
            var samples = Data()
            for await audio in stream {
                if let chunk = PCM16Audio.samples(from: audio.buffer) {
                    samples.append(chunk)
                }
            }
            return samples
        }
    }

    func stop() async -> Data {
        guard isRecording else { return Data() }
        isRecording = false
        capture?.stop()
        capture = nil
        let samples = await task?.value ?? Data()
        task = nil
        return samples
    }

    // Written to a temp file because the on-device analyzer reads an AVAudioFile,
    // and deleted by the caller as soon as both transcribers are done with it.
    static func writeWav(_ samples: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "rewrite-comparison-\(UUID().uuidString).wav")
        try PCM16Audio.wav(from: samples).write(to: url)
        return url
    }
}
