import Foundation

struct ProviderStatus: Equatable, Sendable {
    enum State: Sendable {
        case checking
        case ready
        case waiting
        case unavailable
    }

    let state: State
    let title: String
    let detail: String
    let symbolName: String

    var isReady: Bool { state == .ready }

    static let checking = ProviderStatus(
        state: .checking,
        title: "Checking…",
        detail: "Looking for a local writing model.",
        symbolName: "arrow.trianglehead.2.clockwise.rotate.90"
    )
}
