import Foundation

/// Pure decision logic for Caps Lock as a shortcut modifier.
///
/// Physical Caps is aliased to an inert key (F18) at the HID layer so the OS
/// never applies caps toggle/LED. This machine then gives Caps two roles:
///
///   Caps held + other key → add Caps chord modifiers, let the key through
///   Caps tapped alone     → a real Caps Lock toggle (see `CapsLockState`)
///   Caps held and released slowly, or used as a modifier → nothing
///
/// The tap role is what keeps Caps Lock itself usable. It only fires when no
/// other key was pressed during the hold AND the press was shorter than
/// `tapThreshold`, so holding Caps while thinking never emits stray capitals.
///
/// A max-hold ceiling force-releases a stranded `capsHeld` if the key-up was
/// lost (tap disabled mid-hold, secure input, etc.) — without that, every
/// subsequent keystroke gets the Caps chord ORed on.
enum CapsLockExpanderEvent: Sendable {
    case capsDown
    case capsUp
    case otherKeyDown
    /// OS autorepeat of a non-Caps key (keyboardEventAutorepeat set).
    case otherKeyRepeat
    case otherKeyUp
    /// Synthetic: poll / tap-disabled / wake asked us to abandon a hold.
    case forceRelease
}

struct CapsLockStateMachine: Sendable {
    enum Output: Equatable, Sendable {
        case consume
        case consumeAndToggleCapsLock
        case passUnmodified
        case passWithCapsChord
    }

    /// Longest press still counted as a tap rather than a hold. 0.3s was
    /// verified comfortable on device with the CapsSpike harness.
    static let defaultTapThreshold: TimeInterval = 0.3
    /// Caps held longer than this is treated as stranded — force-release.
    static let defaultMaxHold: TimeInterval = 2.5

    var tapThreshold: TimeInterval = CapsLockStateMachine.defaultTapThreshold
    var maxHold: TimeInterval = CapsLockStateMachine.defaultMaxHold
    var tapTogglesCapsLock = true

    private(set) var capsHeld = false
    private var downAt: TimeInterval = 0
    private var usedAsModifier = false

    mutating func handle(_ event: CapsLockExpanderEvent, at now: TimeInterval) -> Output {
        // Ceiling check on every event so a lost key-up cannot strand forever.
        if capsHeld, event != .forceRelease, (now - downAt) > maxHold {
            capsHeld = false
            usedAsModifier = false
        }

        switch event {
        case .forceRelease:
            capsHeld = false
            usedAsModifier = false
            return .passUnmodified
        case .capsDown:
            // Autorepeat re-sends keyDown while held; only the first starts the clock.
            if !capsHeld {
                downAt = now
                usedAsModifier = false
            }
            capsHeld = true
            return .consume
        case .capsUp:
            let wasHeld = capsHeld
            let wasQuick = wasHeld && (now - downAt) <= tapThreshold
            let shouldToggle = tapTogglesCapsLock && wasHeld && !usedAsModifier && wasQuick
            capsHeld = false
            usedAsModifier = false
            return shouldToggle ? .consumeAndToggleCapsLock : .consume
        case .otherKeyDown:
            guard capsHeld else { return .passUnmodified }
            usedAsModifier = true
            return .passWithCapsChord
        case .otherKeyRepeat:
            // A chord fires once per physical press. Passing autorepeats with
            // the chord re-triggered the target shortcut for as long as the
            // keys stayed down (a held ⇪2 reopened the screenshot tool over
            // and over). Consuming — not passing unmodified — also keeps the
            // repeats from typing the bare character mid-chord.
            guard capsHeld else { return .passUnmodified }
            usedAsModifier = true
            return .consume
        case .otherKeyUp:
            // Chord the release if still held, but do not mark usedAsModifier —
            // a key that went down before Caps must not suppress a Caps tap.
            return capsHeld ? .passWithCapsChord : .passUnmodified
        }
    }
}
