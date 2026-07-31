import Foundation

struct HotkeyDebouncer {
    private var lastFire: Date?
    let interval: TimeInterval

    init(interval: TimeInterval = 0.35) {
        self.interval = interval
    }

    mutating func shouldFire() -> Bool {
        let now = Date()
        if let lastFire, now.timeIntervalSince(lastFire) < interval {
            return false
        }
        lastFire = now
        return true
    }
}
