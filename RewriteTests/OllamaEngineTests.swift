import Foundation
import XCTest
@testable import Rewrite

final class OllamaEngineTests: XCTestCase {
    func testDecodeModelsSortsDeduplicatesAndDropsEmptyNames() throws {
        let data = Data(
            #"""
            {
              "models": [
                { "name": "qwen3:8b" },
                { "name": "" },
                { "name": "llama3.2:3b" },
                { "name": "qwen3:8b" }
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
                "content": "  A clearer sentence.  \n"
              }
            }
            """#.utf8
        )

        let output = try OllamaEngine.decodeRewrite(from: data)

        XCTAssertEqual(output, "A clearer sentence.")
    }

    func testDecodeRewriteRejectsEmptyMessage() {
        let data = Data(
            #"{"message":{"role":"assistant","content":"   "}}"#.utf8
        )

        XCTAssertThrowsError(try OllamaEngine.decodeRewrite(from: data)) { error in
            guard case RewriteEngineError.invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
        }
    }
}
