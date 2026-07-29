import XCTest
@testable import Rewrite

final class OpenAITranscriptionTests: XCTestCase {
    // Push-to-talk knows exactly where the turn ends, and the API treats a
    // missing turn_detection differently from an explicit null, so the null has
    // to survive serialization.
    func testSessionUpdateDisablesTurnDetectionExplicitly() throws {
        let data = OpenAITranscriptionEngine.sessionUpdateData(keywords: [])
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let session = try XCTUnwrap(json["session"] as? [String: Any])
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])

        XCTAssertEqual(session["type"] as? String, "transcription")
        XCTAssertTrue(input["turn_detection"] is NSNull)

        let format = try XCTUnwrap(input["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "audio/pcm")
        XCTAssertEqual(format["rate"] as? Int, 24_000)

        let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])
        XCTAssertEqual(transcription["model"] as? String, "gpt-live-transcribe")
        XCTAssertNil(transcription["keywords"])
    }

    func testSessionUpdateCarriesKeywordsWhenPresent() throws {
        let data = OpenAITranscriptionEngine.sessionUpdateData(keywords: ["Zuora", "REVPRO"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let session = try XCTUnwrap(json["session"] as? [String: Any])
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])

        XCTAssertEqual(transcription["keywords"] as? [String], ["Zuora", "REVPRO"])
    }

    func testAudioIsAppendedAsBase64() throws {
        let samples = Data([0x01, 0x02, 0x03, 0x04])
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: OpenAITranscriptionEngine.appendData(samples: samples)
            ) as? [String: Any]
        )

        XCTAssertEqual(json["type"] as? String, "input_audio_buffer.append")
        XCTAssertEqual(json["audio"] as? String, samples.base64EncodedString())
    }

    // The API rejects the entire request over a stray angle bracket or line
    // break, and these terms come from OCR of arbitrary screen content.
    func testKeywordsAreStrippedOfCharactersTheAPIRejects() {
        let cleaned = PCM16Audio.sanitizedKeywords([
            "<Invoice>", "line\nbreak", "   ", "Zuora"
        ])
        XCTAssertEqual(cleaned, ["Invoice", "line break", "Zuora"])
    }

    func testWavHeaderDescribesTheSamplesItCarries() throws {
        let samples = Data(repeating: 0, count: 480)
        let wav = PCM16Audio.wav(from: samples)

        XCTAssertEqual(wav.count, 44 + samples.count)
        XCTAssertEqual(String(data: wav[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav[8..<12], encoding: .ascii), "WAVE")

        let declaredSampleRate = wav[24..<28].withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self).littleEndian
        }
        XCTAssertEqual(declaredSampleRate, 24_000)

        let declaredDataSize = wav[40..<44].withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self).littleEndian
        }
        XCTAssertEqual(declaredDataSize, UInt32(samples.count))
    }

    func testMultipartBodyNamesTheFileModelAndEachKeyword() throws {
        let body = OpenAITranscriptionEngine.multipartBody(
            boundary: "abc",
            wav: Data([0x00]),
            keywords: ["Zuora", "REVPRO"]
        )
        let text = try XCTUnwrap(String(data: body, encoding: .isoLatin1))

        XCTAssertTrue(text.contains("name=\"model\""))
        XCTAssertTrue(text.contains("gpt-transcribe"))
        XCTAssertEqual(text.components(separatedBy: "name=\"keywords[]\"").count - 1, 2)
        XCTAssertTrue(text.contains("filename=\"dictation.wav\""))
        XCTAssertTrue(text.hasSuffix("--abc--\r\n"))
    }

    func testCleanupPayloadTurnsReasoningOff() throws {
        let payload = OpenAIChatEngine.payload(
            text: "hello there", directive: "tidy this", model: .luna
        )

        XCTAssertEqual(payload["model"] as? String, "gpt-5.6-luna")
        XCTAssertEqual((payload["reasoning"] as? [String: Any])?["effort"] as? String, "none")
        XCTAssertEqual(payload["store"] as? Bool, false)
    }
}
