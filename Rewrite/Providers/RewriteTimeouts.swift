import Foundation

enum RewriteTimeouts {
    /// Status checks should stay responsive even when Ollama is starting.
    static let ollamaDiscovery: TimeInterval = 3

    /// Leaves enough time for a Service invocation to report a useful error.
    static let modelRequest: TimeInterval = 50

    /// `Info.plist` gives macOS Services 60 seconds for the full request.
    static let service: TimeInterval = 55
}
