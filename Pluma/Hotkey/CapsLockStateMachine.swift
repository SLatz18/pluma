import Foundation

/// Pure decision logic for Caps Lock as a shortcut modifier.
///
/// Physical Caps is aliased to an inert key (F18) at the HID layer so the OS
/// never applies caps toggle/LED. This machine then treats that key as:
///
///   Caps down       → swallow it, arm the chord
///   other key while held → add Caps chord modifiers, let it through
///   Caps up         → swallow it, disarm
///
/// A tap of Caps alone does nothing — the same trade Hyperkey makes. Dual-role
/// Caps (modifier + toggle) is out of scope.
enum CapsLockExpanderEvent: Sendable {
    case capsDown
    case capsUp
    case otherKey
}

struct CapsLockStateMachine: Sendable {
    enum Output: Equatable, Sendable {
        case consume
        case passUnmodified
        case passWithCapsChord
    }

    private(set) var capsHeld = false

    mutating func handle(_ event: CapsLockExpanderEvent) -> Output {
        switch event {
        case .capsDown:
            capsHeld = true
            return .consume
        case .capsUp:
            capsHeld = false
            return .consume
        case .otherKey:
            return capsHeld ? .passWithCapsChord : .passUnmodified
        }
    }
}
