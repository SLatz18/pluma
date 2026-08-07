import Foundation

enum RewriteTimeouts {
    /// Service requests must finish before AppKit's documented 30-second limit.
    static let serviceRequest: TimeInterval = 20
    static let service: TimeInterval = 24
}
