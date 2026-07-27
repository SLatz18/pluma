import Foundation
import XCTest
@testable import Rewrite

final class OllamaEngineTests: XCTestCase {
    func testDecodeModelsSortsDeduplicatesAndDropsEmptyNames() throws {
        let data = Data(
            #"""
            {
              "models": [
                {
                  "name": "qwen3:8b",
                  "size": 5000,
                  "digest": "qwen-digest",
                  "details": { "format": "gguf" }
                },
                {
                  "name": "",
                  "size": 1000,
                  "digest": "empty-name",
                  "details": { "format": "gguf" }
                },
                {
                  "name": "llama3.2:3b",
                  "size": 4000,
                  "digest": "llama-digest",
                  "details": { "format": "gguf" }
                },
                {
                  "name": "qwen3:8b",
                  "size": 5000,
                  "digest": "qwen-digest",
                  "details": { "format": "gguf" }
                },
                {
                  "name": "glm-4.7:cloud",
                  "size": 3000,
                  "digest": "remote-digest",
                  "details": { "format": "gguf" }
                },
                {
                  "name": "private-alias",
                  "size": 3000,
                  "digest": "alias-digest",
                  "details": { "format": "gguf" },
                  "remote_model": "glm-4.7",
                  "remote_host": "https://ollama.com:443"
                }
              ]
            }
            """#.utf8
        )

        let models = try OllamaEngine.decodeModels(from: data)

        XCTAssertEqual(models, ["llama3.2:3b", "qwen3:8b"])
    }

    func testDecodeModelsRejectsMalformedPayload() {
        let data = Data(#"{"unexpected":[]}"#.utf8)

        XCTAssertThrowsError(try OllamaEngine.decodeModels(from: data))
    }

    func testDecodeRewriteReturnsTrimmedMessage() throws {
        let data = Data(
            #"""
            {
              "message": {
                "role": "assistant",
                "content": "<rewrite>\nA clearer sentence.\n</rewrite>"
              }
            }
            """#.utf8
        )

        let output = try OllamaEngine.decodeRewrite(
            from: data,
            original: "Original sentence."
        )

        XCTAssertEqual(output, "A clearer sentence.")
    }

    func testDecodeRewriteRejectsEmptyMessage() {
        let data = Data(#"{"message":{"role":"assistant","content":"<rewrite></rewrite>"}}"#.utf8)

        XCTAssertThrowsError(
            try OllamaEngine.decodeRewrite(from: data, original: "Original")
        ) { error in
            guard case RewriteEngineError.invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
        }
    }

    func testChatRequestUsesDeterministicNonStreamingOptions() throws {
        let data = try OllamaEngine.makeChatRequestBody(
            text: "Original",
            intent: .improve,
            model: "qwen3:8b"
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let options = try XCTUnwrap(json["options"] as? [String: Any])

        XCTAssertEqual(json["model"] as? String, "qwen3:8b")
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertEqual((options["seed"] as? NSNumber)?.intValue, 0)
        XCTAssertEqual((options["temperature"] as? NSNumber)?.doubleValue, 0)
    }

    func testModelMetadataFailsClosedWhenLocalEvidenceIsMissing() {
        let data = Data(#"{"models":[{"name":"unknown"}]}"#.utf8)

        XCTAssertThrowsError(try OllamaEngine.decodeModels(from: data))
    }

    func testOllamaEndpointPolicyAllowsOnlyLoopbackHosts() throws {
        XCTAssertTrue(
            LoopbackPolicy.allows(try XCTUnwrap(URL(string: "http://127.0.0.1:11434")))
        )
        XCTAssertFalse(
            LoopbackPolicy.allows(try XCTUnwrap(URL(string: "http://localhost:11434")))
        )
        XCTAssertFalse(
            LoopbackPolicy.allows(try XCTUnwrap(URL(string: "http://[::1]:11434")))
        )
        XCTAssertFalse(
            LoopbackPolicy.allows(try XCTUnwrap(URL(string: "https://ollama.com")))
        )
        XCTAssertFalse(
            LoopbackPolicy.allows(try XCTUnwrap(URL(string: "http://127.0.0.1:11435")))
        )
    }
}
