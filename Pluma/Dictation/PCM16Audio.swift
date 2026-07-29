import AVFoundation

// The realtime socket wants raw little-endian PCM16, and the file endpoint wants
// the same samples inside a WAV container. Both come from the same recording, so
// the session keeps the samples and packages them on demand.
enum PCM16Audio {
    static let sampleRate = 24_000.0

    static var captureFormat: AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        )
    }

    static func samples(from buffer: AVAudioPCMBuffer) -> Data? {
        guard
            let channel = buffer.int16ChannelData,
            buffer.frameLength > 0
        else { return nil }
        return Data(bytes: channel[0], count: Int(buffer.frameLength) * 2)
    }

    // A 44-byte canonical WAV header. The endpoint accepts several containers,
    // but WAV is the one we can write without a framework.
    static func wav(from samples: Data, sampleRate: Int = Int(sampleRate)) -> Data {
        var data = Data()
        let channels = 1
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8

        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + samples.count))
        data.append(contentsOf: Array("WAVE".utf8))

        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(channels))
        append(UInt32(sampleRate))
        append(UInt32(byteRate))
        append(UInt16(channels * bitsPerSample / 8))
        append(UInt16(bitsPerSample))

        data.append(contentsOf: Array("data".utf8))
        append(UInt32(samples.count))
        data.append(samples)
        return data
    }

    // Keywords are hints for the transcriber, but the API rejects the whole
    // request over a stray angle bracket or line break, so OCR text — which can
    // contain anything at all — has to be filtered rather than trusted.
    static func sanitizedKeywords(_ terms: [String]) -> [String] {
        terms.compactMap { term in
            let cleaned = term
                .components(separatedBy: .newlines)
                .joined(separator: " ")
                .replacingOccurrences(of: "<", with: "")
                .replacingOccurrences(of: ">", with: "")
                .trimmingCharacters(in: .whitespaces)
            return cleaned.isEmpty ? nil : cleaned
        }
    }
}
