import Foundation

// The file endpoint, used both as the realtime socket's safety net and by the
// comparison, where two transcribers have to be given byte-identical audio.
enum OpenAIFileTranscriber {
    static let model = "gpt-transcribe"

    private static let endpoint = URL(
        string: "https://api.openai.com/v1/audio/transcriptions"
    )!

    static func transcribe(
        wav: Data,
        keywords: [String],
        session: URLSession = .shared
    ) async throws -> String {
        guard let key = OpenAIKey.current else {
            throw OpenAITranscriptionError.missingKey
        }

        let boundary = "rewrite-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = multipartBody(boundary: boundary, wav: wav, keywords: keywords)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw RewriteEngineError.modelUnavailable("OpenAI returned HTTP \(http.statusCode)")
        }
        let decoded = try JSONDecoder().decode(Reply.self, from: data)
        return DictationTranscript.assemble(decoded.text)
    }

    static func multipartBody(boundary: String, wav: Data, keywords: [String]) -> Data {
        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }

        appendField("model", model)
        for keyword in keywords {
            appendField("keywords[]", keyword)
        }

        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(
            Data(
                "Content-Disposition: form-data; name=\"file\"; filename=\"dictation.wav\"\r\n".utf8
            )
        )
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    private struct Reply: Decodable {
        let text: String
    }
}
