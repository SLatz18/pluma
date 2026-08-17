import AVFoundation
import XCTest

@testable import Pluma

final class AudioCaptureSessionTests: XCTestCase {
    // The regression this guards: stop() used to finish the audio stream from a
    // queue hop that captured self weakly, while both transcription engines
    // release the session on the very next line. The finish was skipped, the
    // stream stayed open, and the analyzer waited for an end of input that never
    // arrived — dictation's HUD stuck on "Transcribing…" with no text inserted.
    func testStopEndsTheStreamEvenWhenTheSessionIsReleasedImmediately() async throws {
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)
        )
        var session: AudioCaptureSession? = AudioCaptureSession(targetFormat: format)

        let stream: AsyncStream<CapturedAudio>
        do {
            stream = try XCTUnwrap(session).start()
        } catch {
            throw XCTSkip("No usable microphone in this environment: \(error)")
        }

        session?.stop()
        session = nil

        let drained = await Self.drains(stream, within: .seconds(3))
        XCTAssertTrue(
            drained,
            "stop() must end the audio stream so the analyzer sees end of input"
        )
    }

    // Cancelling the group unblocks the drain, so a regression fails the test
    // instead of hanging the suite.
    private static func drains(
        _ stream: AsyncStream<CapturedAudio>,
        within timeout: Duration
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in stream {}
                return true
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let drained = await group.next() ?? false
            group.cancelAll()
            return drained
        }
    }
}
