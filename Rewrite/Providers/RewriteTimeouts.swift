import Foundation

enum RewriteTimeouts {
    /// Status checks should stay responsive even when Ollama is starting.
    static let ollamaDiscovery: TimeInterval = 3

    /// Interactive requests can wait longer without blocking another app.
    static let modelRequest: TimeInterval = 50

    /// Service requests must finish before AppKit's documented 30-second limit.
    static let serviceRequest: TimeInterval = 20
    static let service: TimeInterval = 24
}
