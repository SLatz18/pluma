import Foundation

// The way into developer mode: ↑ ↑ ↓ ↓ ← → ← →, entered anywhere in the pluma
// window. Arrows only, so it can be typed with a text field focused without
// inserting anything — which a typed word could not manage.
//
// Deliberately free of AppKit so the whole sequence, including its timeout, can
// be tested without synthesising key events.
struct CheatCodeRecognizer {
    static let sequence: [UInt16] = [
        126, 126,   // ↑ ↑
        125, 125,   // ↓ ↓
        123, 124,   // ← →
        123, 124    // ← →
    ]

    // A pause long enough that the user has moved on to something else. Partial
    // attempts expire silently rather than lying in wait.
    static let interKeyTimeout: Duration = .seconds(2)

    private var progress = 0
    private var lastKeyAt: ContinuousClock.Instant?

    init() {}

    /// Feeds one key press in. Returns true on the press that completes the
    /// sequence, and resets so the next full entry matches again.
    mutating func accept(keyCode: UInt16, at now: ContinuousClock.Instant) -> Bool {
        if let lastKeyAt, now - lastKeyAt > Self.interKeyTimeout {
            progress = 0
        }
        lastKeyAt = now

        if keyCode == Self.sequence[progress] {
            progress += 1
        } else {
            // A wrong key ends this attempt, but the key itself may be the start
            // of the next one — so ↑ ↑ ↑ ↓ ↓ … still works.
            progress = keyCode == Self.sequence[0] ? 1 : 0
        }

        guard progress == Self.sequence.count else { return false }
        progress = 0
        lastKeyAt = nil
        return true
    }
}
