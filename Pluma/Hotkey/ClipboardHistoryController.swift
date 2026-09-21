import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// ⇪4 opens macOS Spotlight's built-in clipboard history.
///
/// macOS ships no bindable clipboard-history action, so there is nothing to
/// register against directly. That was established rather than assumed: the
/// full shipped `DefaultShortcutsTable.xml` (105 IDs) has no clipboard entry,
/// a `CGSGetSymbolicHotKeyValue` sweep of IDs 0-4095 found 229 recognized and
/// none on ⌘4, Spotlight's `application:openURLs:` matches exactly
/// `spotlight://apps`, its App Intents metadata has zero actions, and
/// ActionKit ships only `Get Clipboard` / `Copy to Clipboard`. Apple's own
/// documented route is: open Spotlight, then press ⌘4. So that is the route
/// pluma automates.
///
/// Shape of the feature, and why each piece is where it is:
///
/// - **Nothing is posted from the event tap.** `CapsLockExpander`'s tap only
///   ORs the Caps chord onto a keystroke and passes it through; the Carbon
///   hotkey then consumes it. So this controller runs on the main Carbon event
///   dispatcher, never on the tap thread. Posting synthetic events from inside
///   a tap callback is how taps deadlock or get disabled by the system.
/// - **Every posted event is marked** (`SyntheticEventMarker`), so the tap
///   returns `.passUnmodified` for it and the chord is never ORed onto our own
///   keystrokes. The synthetic ⌘4 also carries only `.maskCommand`, never
///   ⌃⌥⌘, so Carbon cannot re-trigger this slot from it either.
/// - **Readiness is observed, never slept on.** A fixed delay is the
///   flaky-on-a-loaded-machine failure; this polls for Spotlight's window.
/// - **An already-open Spotlight is not toggled shut.** The same probe answers
///   that, so ⌘Space is skipped when Spotlight is already up.
@MainActor
final class ClipboardHistoryController {
    /// SwiftUI re-initializes `App` structs and `@StateObject(wrappedValue:)`
    /// autoclosures are lazy, so a hotkey owner must be a singleton or it
    /// either double-registers or — for a controller with no UI referencing
    /// it — never gets built at all. Started explicitly from the app delegate.
    static let shared = ClipboardHistoryController()

    /// Hardcoded ⇪4, not a Preferences-backed recordable shortcut: the
    /// existing per-shortcut pattern costs three UserDefaults keys, a
    /// getter/setter pair, a `syncCapsChordShortcuts` entry and two UI
    /// surfaces, which is a settings subsystem rather than a nearly-free
    /// reuse. See PLAN.md.
    static let keyCode = UInt32(kVK_ANSI_4)

    /// How long to wait for Spotlight's window after ⌘Space. On timeout the
    /// sequence BAILS rather than sending ⌘4 blind — see `openHistory()`.
    private static let readinessTimeout: Duration = .seconds(1)
    private static let readinessPollInterval: Duration = .milliseconds(25)

    /// The initiating chord has to clear before ⌘Space is posted, or the
    /// synthetic event picks up the user's still-held modifiers and becomes
    /// some other app's global shortcut.
    private static let modifierReleaseTimeout: Duration = .seconds(2)
    private static let modifierPollInterval: Duration = .milliseconds(10)
    // nonisolated so the pure `hasHeldShortcutModifiers` check stays callable
    // off the main actor; a static on a @MainActor type is isolated by default.
    nonisolated private static let shortcutModifierMask: CGEventFlags = [
        .maskControl,
        .maskAlternate,
        .maskCommand,
        .maskShift
    ]

    private let hotkey = HotkeyManager()
    private let probe: any SpotlightPresenceProbing
    private let defaults: UserDefaults
    private var started = false

    /// A mashed ⇪4 must not stack a second sequence on a live one: two
    /// overlapping runs would post ⌘Space twice and toggle Spotlight shut.
    private var isRunning = false

    init(
        probe: any SpotlightPresenceProbing = SpotlightPresence(),
        defaults: UserDefaults = .standard
    ) {
        self.probe = probe
        self.defaults = defaults
    }

    // MARK: - Registration

    func start() {
        guard !started else { return }
        started = true

        hotkey.onPress = { [weak self] slot in
            guard slot == .clipboardHistory else { return }
            Task { @MainActor [weak self] in
                await self?.openClipboardHistory()
            }
        }
        // Deliberately no `onRelease`: this is a one-shot action, not
        // push-to-talk like dictation. Acting on both edges would run the
        // whole sequence twice per press — and the second ⌘Space would close
        // the Spotlight the first one opened.

        register()

        NotificationCenter.default.addObserver(
            forName: .capsShortcutsSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.register()
            }
        }
    }

    /// The registered chord has to be recomputed, not stored as a constant.
    /// `CapsLockExpander.reevaluate()` sets the tap's chord from
    /// `capsChordIncludesShift`, so with that setting on the tap delivers
    /// ⌃⌥⌘⇧4 and a hardcoded ⌃⌥⌘4 registration would never fire — the
    /// feature would be silently dead with nothing in the logs.
    private func register() {
        hotkey.register(currentShortcut(), in: .clipboardHistory)
    }

    func currentShortcut() -> GlobalShortcut {
        GlobalShortcut(
            keyCode: Self.keyCode,
            carbonModifiers: GlobalShortcut.capsChordModifiers(
                includesShift: Preferences.capsChordIncludesShift(from: defaults)
            ),
            display: GlobalShortcut.clipboardHistoryDefault.display
        )
    }

    // MARK: - The sequence

    private func openClipboardHistory() async {
        guard !isRunning else {
            DebugLog.log("clipboard history: ignored — a sequence is already running", at: .quiet)
            return
        }
        isRunning = true
        defer { isRunning = false }

        guard await waitForShortcutModifiersToRelease() else {
            DebugLog.log("clipboard history: bailed — Caps chord never released")
            return
        }

        switch ClipboardHistoryPlan.forSpotlight(isOnScreen: probe.isSpotlightOnScreen()) {
        case .historyOnly:
            // Spotlight is already up. Re-posting ⌘Space here is the bug that
            // would close it instead of showing history.
            DebugLog.log("clipboard history: Spotlight already open — sending ⌘4 only")
            postHistoryShortcut()
        case .openThenHistory:
            guard postSpotlightShortcut() else {
                DebugLog.log("clipboard history: bailed — could not create the ⌘Space event")
                return
            }
            guard await waitForSpotlight() else {
                // Deliberately do NOT fall through to ⌘4. If the readiness
                // probe is wrong, a blind ⌘4 goes to whatever has focus; this
                // way the worst case is an open Spotlight with no history
                // panel, dismissed with Escape, with the cause logged.
                DebugLog.log("clipboard history: bailed — Spotlight did not appear within \(Self.readinessTimeout)")
                return
            }
            postHistoryShortcut()
        }
    }

    /// The expander never sets real system modifier flags — it ORs the chord
    /// onto individual events — so a live Caps hold is invisible to
    /// `CGEventSource.flagsState`. Both sources have to be polled. (Same
    /// two-part condition as Reader's copy path; duplicated on purpose rather
    /// than refactoring Reader, so this change cannot regress that path.)
    private func waitForShortcutModifiersToRelease() async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.modifierReleaseTimeout)

        while Self.hasHeldShortcutModifiers(CGEventSource.flagsState(.hidSystemState))
            || CapsLockExpander.shared.isCapsChordHeld {
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: Self.modifierPollInterval)
        }
        return true
    }

    nonisolated static func hasHeldShortcutModifiers(_ flags: CGEventFlags) -> Bool {
        !flags.intersection(shortcutModifierMask).isEmpty
    }

    /// Observed readiness, not a fixed sleep: poll until Spotlight actually
    /// owns an on-screen window, or give up.
    private func waitForSpotlight() async -> Bool {
        let clock = ContinuousClock()
        let started = clock.now
        let deadline = started.advanced(by: Self.readinessTimeout)

        while !probe.isSpotlightOnScreen() {
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: Self.readinessPollInterval)
        }
        DebugLog.log(
            "clipboard history: Spotlight ready after \(started.duration(to: clock.now))",
            at: .quiet
        )
        return true
    }

    // MARK: - Synthetic keystrokes

    private func postSpotlightShortcut() -> Bool {
        post(virtualKey: CGKeyCode(kVK_Space))
    }

    private func postHistoryShortcut() {
        _ = post(virtualKey: CGKeyCode(kVK_ANSI_4))
    }

    private func post(virtualKey: CGKeyCode) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        else { return false }

        // Exactly ⌘, never the Caps chord. Two reasons: Spotlight only answers
        // to ⌘Space/⌘4, and a ⌃⌥⌘4 would re-trigger this very hotkey.
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        // Marked so pluma's own tap and edit monitors leave these alone —
        // without this the tap ORs the Caps chord onto them and re-catches
        // its own keystrokes.
        SyntheticEventMarker.mark(keyDown)
        SyntheticEventMarker.mark(keyUp)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}

/// Whether ⌘Space is needed first, or Spotlight is already up and only ⌘4 is.
/// Split out as a pure value so the "do not toggle an open Spotlight closed"
/// rule is testable without a live Spotlight.
enum ClipboardHistoryPlan: Equatable, Sendable {
    /// Spotlight is closed: open it, wait for it, then ask for history.
    case openThenHistory
    /// Spotlight is already up — sending ⌘Space now would close it.
    case historyOnly

    static func forSpotlight(isOnScreen: Bool) -> ClipboardHistoryPlan {
        isOnScreen ? .historyOnly : .openThenHistory
    }
}

protocol SpotlightPresenceProbing: Sendable {
    func isSpotlightOnScreen() -> Bool
}

/// Is Spotlight's panel on screen right now?
///
/// Process presence is useless here: `com.apple.Spotlight` is always resident.
/// Window presence is the signal, and it was measured on macOS 26.7 with
/// Spotlight closed — it owns three windows (64x64 at layer 0, 844x607 at
/// layer 23, and a 640x56 search field at alpha 0.0) and **none of them are in
/// the on-screen list**. So an on-screen, non-transparent, panel-width window
/// means open.
struct SpotlightPresence: SpotlightPresenceProbing {
    static let bundleID = "com.apple.Spotlight"

    /// Both real surfaces (640-wide field, 844-wide results) clear this; the
    /// 64x64 window that exists even when Spotlight is closed does not.
    /// A width threshold rather than `kCGWindowLayer == 23` on purpose — a
    /// window level is exactly the sort of constant an OS update moves.
    static let minimumWidth = 200.0

    func isSpotlightOnScreen() -> Bool {
        guard let pid = Self.spotlightProcessIdentifier() else { return false }
        return Self.hasOnScreenPanel(ownedBy: pid)
    }

    static func spotlightProcessIdentifier() -> pid_t? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first?
            .processIdentifier
    }

    /// Matched by owner PID, never by `kCGWindowOwnerName`. Window *names* are
    /// the field that requires Screen Recording; owner PID, bounds, alpha and
    /// on-screen state are unrestricted. So this probe needs no new TCC grant.
    static func hasOnScreenPanel(ownedBy pid: pid_t) -> Bool {
        guard
            let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else { return false }

        return windows.contains { matchesSpotlightPanel($0, pid: pid) }
    }

    /// Pure, so the predicate is testable against captured window dictionaries.
    static func matchesSpotlightPanel(_ window: [String: Any], pid: pid_t) -> Bool {
        guard
            let owner = window[kCGWindowOwnerPID as String] as? Int,
            owner == Int(pid)
        else { return false }
        // The search field sits at alpha 0 while closed.
        guard let alpha = window[kCGWindowAlpha as String] as? Double, alpha > 0 else {
            return false
        }
        guard
            let bounds = window[kCGWindowBounds as String] as? [String: Any],
            let width = bounds["Width"] as? Double
        else { return false }
        return width >= minimumWidth
    }
}
