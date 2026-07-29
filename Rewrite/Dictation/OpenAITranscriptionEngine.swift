import AVFoundation
import Foundation

enum OpenAITranscriptionError: LocalizedError {
    case missingKey
    case noAudioFormat

    var errorDescription: String? {
        switch self {
        case .missingKey: "Add your OpenAI API key in settings"
        case .noAudioFormat: "No compatible audio format for dictation"
        }
    }
}

// Streams microphone audio to OpenAI's realtime transcription socket for live
// text, while keeping every sample locally so the same utterance can be sent to
// the file endpoint if the socket produces nothing. Losing what the user said is
// never acceptable, and a dropped socket is the likeliest way for that to happen.
@MainActor
final class OpenAITranscriptionEngine: DictationTranscribing {
    nonisolated static let liveModel = "gpt-live-transcribe"

    private(set) var availability: TranscriptionAvailability = .checking {
        didSet {
            guard availability != oldValue else { return }
            onAvailabilityChange?(availability)
        }
    }

    var onAvailabilityChange: ((TranscriptionAvailability) -> Void)?
    var onVolatileText: ((String) -> Void)?

    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var capture: AudioCaptureSession?
    private var pumpTask: Task<Data, Never>?
    private var receiveTask: Task<Void, Never>?

    private var recordedSamples = Data()
    private var liveText = ""
    private var finalTranscript: String?
    private var keywords: [String] = []
    private var socketFailed = false
    private var usedFallback = false

    // How long to wait for the final transcript after committing the turn. The
    // fallback covers anything slower, so this only needs to outlast a healthy
    // response.
    private static let completionTimeout: Duration = .seconds(10)

    init(session: URLSession = .shared) {
        self.session = session
    }

    func prepare() async {
        availability = OpenAIKey.isPresent
            ? .ready
            : .unsupported(OpenAITranscriptionError.missingKey.localizedDescription)
    }

    func start(contextStrings: @Sendable () async -> [String]) async throws {
        guard let key = OpenAIKey.current else {
            availability = .unsupported(OpenAITranscriptionError.missingKey.localizedDescription)
            throw OpenAITranscriptionError.missingKey
        }
        guard let format = PCM16Audio.captureFormat else {
            throw OpenAITranscriptionError.noAudioFormat
        }

        recordedSamples = Data()
        liveText = ""
        finalTranscript = nil
        socketFailed = false
        usedFallback = false

        // The microphone opens before the socket is configured for the same
        // reason it opens before OCR runs: the stream buffers, so nothing spoken
        // in the first moments is lost to setup.
        let capture = AudioCaptureSession(targetFormat: format)
        self.capture = capture
        let stream = try capture.start()

        let socket = session.webSocketTask(with: Self.realtimeRequest(key: key))
        self.socket = socket
        socket.resume()
        startReceiving(from: socket)

        keywords = PCM16Audio.sanitizedKeywords(await contextStrings())
        try? await socket.send(
            .data(Self.sessionUpdateData(keywords: keywords))
        )

        pumpTask = Task { [weak self] in
            var recorded = Data()
            for await audio in stream {
                guard let samples = PCM16Audio.samples(from: audio.buffer) else { continue }
                recorded.append(samples)
                do {
                    try await socket.send(.data(Self.appendData(samples: samples)))
                } catch {
                    self?.markSocketFailed(error)
                }
            }
            return recorded
        }
    }

    func finish() async -> String {
        capture?.stop()
        capture = nil

        recordedSamples = await pumpTask?.value ?? Data()
        pumpTask = nil

        if let socket, !socketFailed {
            try? await socket.send(.data(Self.commitData()))
            await waitForFinalTranscript()
        }

        var transcript = finalTranscript.map(DictationTranscript.assemble) ?? ""
        if transcript.isEmpty {
            DebugLog.log("realtime transcript empty; falling back to file endpoint")
            transcript = await transcribeRecording() ?? ""
        }

        teardown()
        return transcript
    }

    func cancel() async {
        capture?.stop()
        capture = nil
        pumpTask?.cancel()
        pumpTask = nil
        teardown()
        recordedSamples = Data()
        liveText = ""
        finalTranscript = nil
    }

    // MARK: - Socket

    private func startReceiving(from socket: URLSessionWebSocketTask) {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    guard let text = Self.text(of: message) else { continue }
                    self?.handle(event: text)
                } catch {
                    self?.markSocketFailed(error)
                    return
                }
            }
        }
    }

    private func handle(event json: String) {
        guard
            let data = json.data(using: .utf8),
            let event = try? JSONDecoder().decode(RealtimeEvent.self, from: data)
        else { return }

        switch event.type {
        case "conversation.item.input_audio_transcription.delta":
            guard let delta = event.delta else { return }
            liveText += delta
            onVolatileText?(DictationTranscript.assemble(liveText))
        case "conversation.item.input_audio_transcription.completed":
            finalTranscript = event.transcript
        case "error":
            DebugLog.log("realtime error: \(event.error?.message ?? "unknown")")
            socketFailed = true
        default:
            break
        }
    }

    private func markSocketFailed(_ error: Error) {
        guard !socketFailed else { return }
        socketFailed = true
        DebugLog.log("realtime socket failed: \(error.localizedDescription)")
    }

    // Polled rather than continuation-based on purpose: the socket can finish,
    // fail, or say nothing at all, and a 50ms poll cannot leak or double-resume
    // the way three racing paths into one continuation can.
    private func waitForFinalTranscript() async {
        let deadline = ContinuousClock.Instant.now + Self.completionTimeout
        while finalTranscript == nil, !socketFailed, ContinuousClock.Instant.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func teardown() {
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    // MARK: - File endpoint fallback

    private func transcribeRecording() async -> String? {
        guard !recordedSamples.isEmpty else { return nil }
        usedFallback = true
        do {
            return try await OpenAIFileTranscriber.transcribe(
                wav: PCM16Audio.wav(from: recordedSamples),
                keywords: keywords,
                session: session
            )
        } catch {
            DebugLog.log("file transcription failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Payloads

    nonisolated static func realtimeRequest(key: String) -> URLRequest {
        var request = URLRequest(
            url: URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!
        )
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        return request
    }

    // turn_detection is explicitly null, not omitted: push-to-talk already knows
    // exactly where the turn ends, so letting a voice-activity detector guess
    // would cut sentences off mid-thought.
    nonisolated static func sessionUpdatePayload(keywords: [String]) -> [String: Any] {
        var transcription: [String: Any] = [
            "model": liveModel,
            "delay": "low"
        ]
        if !keywords.isEmpty {
            transcription["keywords"] = keywords
        }

        return [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": Int(PCM16Audio.sampleRate)],
                        "transcription": transcription,
                        "turn_detection": NSNull()
                    ]
                ]
            ]
        ]
    }

    nonisolated static func sessionUpdateData(keywords: [String]) -> Data {
        (try? JSONSerialization.data(withJSONObject: sessionUpdatePayload(keywords: keywords)))
            ?? Data()
    }

    nonisolated static func appendData(samples: Data) -> Data {
        (try? JSONSerialization.data(
            withJSONObject: [
                "type": "input_audio_buffer.append",
                "audio": samples.base64EncodedString()
            ]
        )) ?? Data()
    }

    nonisolated static func commitData() -> Data {
        (try? JSONSerialization.data(withJSONObject: ["type": "input_audio_buffer.commit"]))
            ?? Data()
    }

    nonisolated private static func text(of message: URLSessionWebSocketTask.Message) -> String? {
        switch message {
        case .string(let text): text
        case .data(let data): String(data: data, encoding: .utf8)
        @unknown default: nil
        }
    }

    private struct RealtimeEvent: Decodable {
        struct ErrorBody: Decodable {
            let message: String?
        }

        let type: String
        let delta: String?
        let transcript: String?
        let error: ErrorBody?
    }

}
