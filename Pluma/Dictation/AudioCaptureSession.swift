import AVFoundation

// AVAudioPCMBuffer predates Sendable and isn't marked, but each buffer here is
// freshly converted, handed off once, and never touched again by the producer.
struct CapturedAudio: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

enum AudioCaptureError: LocalizedError {
    case noInputDevice
    case configurationFailed

    var errorDescription: String? {
        switch self {
        case .noInputDevice: "No microphone is available"
        case .configurationFailed: "The microphone could not be started"
        }
    }
}

// AVAudioEngine's installTap never fires for Bluetooth input devices on
// macOS 26, so capture runs through AVCaptureSession instead. The cost is
// converting each CMSampleBuffer into the format the analyzer asked for.
final class AudioCaptureSession: NSObject, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let captureQueue = DispatchQueue(label: "com.scottlatz.Pluma.audio-capture")
    private let targetFormat: AVAudioFormat

    // Everything below is touched only on captureQueue.
    private var continuation: AsyncStream<CapturedAudio>.Continuation?
    private var converter: AVAudioConverter?
    private var converterSourceFormat: AVAudioFormat?

    init(targetFormat: AVAudioFormat) {
        self.targetFormat = targetFormat
        super.init()
    }

    func start() throws -> AsyncStream<CapturedAudio> {
        // The pinned device when one is selected and connected, otherwise the
        // system default — resolved fresh each session so replugging a mic or
        // changing the setting takes effect on the next press.
        guard let device = MicrophoneSelection.captureDevice() else {
            throw AudioCaptureError.noInputDevice
        }

        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw AudioCaptureError.configurationFailed
        }
        session.addInput(input)

        output.setSampleBufferDelegate(self, queue: captureQueue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw AudioCaptureError.configurationFailed
        }
        session.addOutput(output)
        session.commitConfiguration()

        let (stream, continuation) = AsyncStream.makeStream(of: CapturedAudio.self)
        captureQueue.sync {
            self.continuation = continuation
            self.converter = nil
            self.converterSourceFormat = nil
        }

        // startRunning blocks until the device is live; keep it off the caller.
        // Captures self (queue-confined, @unchecked Sendable) rather than the
        // non-Sendable session directly.
        captureQueue.async { [self] in
            session.startRunning()
        }

        return stream
    }

    func stop() {
        session.stopRunning()
        captureQueue.async { [weak self] in
            self?.continuation?.finish()
            self?.continuation = nil
        }
        session.beginConfiguration()
        for input in session.inputs {
            session.removeInput(input)
        }
        if session.outputs.contains(output) {
            session.removeOutput(output)
        }
        session.commitConfiguration()
    }
}

extension AudioCaptureSession: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let continuation else { return }
        guard let source = Self.pcmBuffer(from: sampleBuffer) else { return }

        guard let converted = convert(source) else { return }
        continuation.yield(CapturedAudio(buffer: converted))
    }

    private func convert(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if source.format == targetFormat { return source }

        if converterSourceFormat != source.format {
            converter = AVAudioConverter(from: source.format, to: targetFormat)
            converterSourceFormat = source.format
        }
        guard let converter else { return nil }

        let ratio = targetFormat.sampleRate / source.format.sampleRate
        let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 1_024
        guard
            let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity)
        else { return nil }

        var error: NSError?
        // convert() runs this block synchronously before returning, so sharing
        // this state with the @Sendable block never actually crosses threads.
        nonisolated(unsafe) var consumed = false
        nonisolated(unsafe) let input = source
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return input
        }

        switch status {
        case .haveData, .inputRanDry:
            return output.frameLength > 0 ? output : nil
        case .endOfStream:
            return nil
        case .error:
            DebugLog.log("audio convert failed: \(error?.localizedDescription ?? "unknown")", at: .quiet)
            return nil
        @unknown default:
            return nil
        }
    }

    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
                formatDescription
            ),
            let format = AVAudioFormat(streamDescription: streamDescription)
        else { return nil }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard
            frameCount > 0,
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)
            )
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else { return nil }
        return buffer
    }
}
