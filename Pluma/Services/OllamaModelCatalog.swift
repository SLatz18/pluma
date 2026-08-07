import Foundation

// One shared fetch of the local Ollama model list. Four surfaces (Home,
// Overview, Settings, Dictation) each hit /api/tags on every appearance,
// but the list only changes when someone installs or removes a model —
// so a short-lived cache answers repeat page visits and concurrent asks
// share one request. Only success is cached: an unreachable Ollama stays
// uncached so "start Ollama, then check again" works immediately.
@MainActor
final class OllamaModelCatalog {
    static let shared = OllamaModelCatalog()

    private let fetch: @Sendable () async throws -> [String]
    private let maxAge: TimeInterval
    private var cached: [String] = []
    private var fetchedAt: Date?
    private var inFlight: Task<[String], Error>?

    init(
        maxAge: TimeInterval = 60,
        fetch: @escaping @Sendable () async throws -> [String] = {
            try await OllamaEngine().availableModels()
        }
    ) {
        self.maxAge = maxAge
        self.fetch = fetch
    }

    func models(forceRefresh: Bool = false) async throws -> [String] {
        if !forceRefresh, let fetchedAt,
           Date.now.timeIntervalSince(fetchedAt) < maxAge {
            return cached
        }
        if let inFlight {
            return try await inFlight.value
        }

        let task = Task { [fetch] in try await fetch() }
        inFlight = task
        defer { inFlight = nil }

        do {
            let fresh = try await task.value
            cached = fresh
            fetchedAt = .now
            return fresh
        } catch {
            cached = []
            fetchedAt = nil
            throw error
        }
    }
}
