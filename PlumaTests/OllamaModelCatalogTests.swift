import XCTest
@testable import Pluma

@MainActor
final class OllamaModelCatalogTests: XCTestCase {
    private actor FetchCounter {
        private(set) var count = 0
        func bump() { count += 1 }
    }

    func testFreshCacheAnswersWithoutRefetching() async throws {
        let counter = FetchCounter()
        let catalog = OllamaModelCatalog(maxAge: 60) {
            await counter.bump()
            return ["gemma"]
        }

        _ = try await catalog.models()
        let second = try await catalog.models()

        XCTAssertEqual(second, ["gemma"])
        let fetches = await counter.count
        XCTAssertEqual(fetches, 1)
    }

    func testForceRefreshBypassesTheCache() async throws {
        let counter = FetchCounter()
        let catalog = OllamaModelCatalog(maxAge: 60) {
            await counter.bump()
            return ["gemma"]
        }

        _ = try await catalog.models()
        _ = try await catalog.models(forceRefresh: true)

        let fetches = await counter.count
        XCTAssertEqual(fetches, 2)
    }

    func testExpiredCacheRefetches() async throws {
        let counter = FetchCounter()
        let catalog = OllamaModelCatalog(maxAge: 0) {
            await counter.bump()
            return ["gemma"]
        }

        _ = try await catalog.models()
        _ = try await catalog.models()

        let fetches = await counter.count
        XCTAssertEqual(fetches, 2)
    }

    func testFailureIsNotCached() async throws {
        let counter = FetchCounter()
        let catalog = OllamaModelCatalog(maxAge: 60) {
            await counter.bump()
            let count = await counter.count
            if count == 1 { throw URLError(.cannotConnectToHost) }
            return ["gemma"]
        }

        // The unreachable server surfaces as an error...
        do {
            _ = try await catalog.models()
            XCTFail("first fetch should throw")
        } catch {}

        // ...and the very next ask goes back to the network, so "start
        // Ollama, then check again" works without waiting out a TTL.
        let recovered = try await catalog.models()
        XCTAssertEqual(recovered, ["gemma"])
    }

    func testConcurrentAsksShareOneFetch() async throws {
        let counter = FetchCounter()
        let catalog = OllamaModelCatalog(maxAge: 0) {
            await counter.bump()
            try? await Task.sleep(for: .milliseconds(50))
            return ["gemma"]
        }

        async let first = catalog.models()
        async let second = catalog.models()
        _ = try await (first, second)

        let fetches = await counter.count
        XCTAssertEqual(fetches, 1)
    }
}
