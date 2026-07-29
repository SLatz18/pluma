import Foundation

// The dual-role decision logic behind the Caps Lock expander, kept pure so
// the press/release ordering is fully unit-testable:
//
//   Caps Lock down       → swallow it, arm the chord
//   other key while held → add the hyper modifiers, let it through
//   Caps Lock up         → swallow it, disarm
//
// A tap of Caps Lock alone does nothing: macOS reasserts caps state from the
// physical keyboard, so a synthetic reinjected toggle can't stick (measured
// on macOS 26 — the state reverts and confuses subsequent presses). That is
// the same trade Hyperkey makes; the toggle comes back the moment the
// expander is off.
enum ExpanderEvent {
    case capsDown
    case capsUp
    case otherKey
}

struct CapsLockStateMachine {
    enum Output {
        case consume
        case passUnmodified
        case passWithHyper
    }

    private(set) var capsHeld = false

    mutating func handle(_ event: ExpanderEvent) -> Output {
        switch event {
        case .capsDown:
            capsHeld = true
            return .consume
        case .capsUp:
            capsHeld = false
            return .consume
        case .otherKey:
            return capsHeld ? .passWithHyper : .passUnmodified
        }
    }
}
