import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    /// Posted when Caps shortcut enablement or Caps chord (with/without Shift) changes.
    static let capsShortcutsSettingsDidChange = Notification.Name("pluma.capsShortcutsSettingsDidChange")
}

/// F18 after HID remap — Carbon/Cocoa keycode.
///
/// File scope on purpose. Everything the CGEventTap callback touches must be
/// nonisolated: nesting these inside the `@MainActor` expander made them
/// MainActor-isolated, and once the tap moved to its own thread the runtime
/// isolation check trapped (`swift_task_checkIsolated` → SIGTRAP) on the first
/// keystroke. Repo rule: no actor hops in C callbacks.
private let capsAliasKeyCode = Int64(kVK_F18)

/// Serial queue for IOKit toggles — never block the event-tap callback.
private let capsLockIOQueue = DispatchQueue(label: "com.scottlatz.Pluma.capsLockIO")

enum CapsTapVerdict: Sendable {
    case consume
    case consumeAndToggleCapsLock
    case passUnmodified
    case passWithCapsChord
}

/// Shared with the C callback — no actor hops, NSLock only.
final class CapsTapState: @unchecked Sendable {
    let lock = NSLock()
    var machine = CapsLockStateMachine()
    var tap: CFMachPort?
    var capsFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
    /// Run-loop the tap source lives on (dedicated thread).
    var runLoop: CFRunLoop?

    func configure(tapToggles: Bool, threshold: TimeInterval) {
        lock.lock()
        machine.tapTogglesCapsLock = tapToggles
        machine.tapThreshold = threshold
        lock.unlock()
    }

    func forceReleaseHold() {
        lock.lock()
        _ = machine.handle(.forceRelease, at: CFAbsoluteTimeGetCurrent())
        lock.unlock()
    }

    /// Poll path: the ceiling inside `handle` clears only a hold that outlived
    /// `maxHold`, so a legitimate in-progress hold survives the tick.
    func abandonStrandedHold() {
        lock.lock()
        if machine.capsHeld {
            _ = machine.handle(.otherKeyUp, at: CFAbsoluteTimeGetCurrent())
        }
        lock.unlock()
    }

    func currentCapsFlags() -> CGEventFlags {
        lock.lock()
        defer { lock.unlock() }
        return capsFlags
    }

    /// Whether a Caps hold is live right now. The expander never sets real
    /// system modifier flags (it ORs the chord onto individual events), so
    /// code that waits for "the chord to be released" — Reader's copy — must
    /// ask the machine, not `CGEventSource.flagsState`.
    func isCapsHeld() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return machine.capsHeld
    }

    func verdict(
        type: CGEventType,
        keyCode: Int64,
        isSynthetic: Bool = false,
        isAutorepeat: Bool = false
    ) -> CapsTapVerdict {
        lock.lock()
        defer { lock.unlock() }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            // The keystroke that tripped this is already gone, which is why the
            // hold that triggers it appears to do nothing. Logged so the cause
            // is visible instead of being guessed at.
            DebugLog.log(
                "caps expander: tap disabled by "
                    + (type == .tapDisabledByTimeout ? "timeout" : "user input")
                    + " — re-enabled, this keystroke was dropped",
                at: .quiet
            )
            // A disable mid-hold loses the Caps key-up — abandon the hold
            // so ordinary typing does not inherit the Caps chord.
            _ = machine.handle(.forceRelease, at: CFAbsoluteTimeGetCurrent())
            return .passUnmodified
        }

        // Pluma's own synthetic events (Reader's ⌘C, dictation's ⌘V) must pass
        // untouched and must not advance the machine: ORing the Caps chord onto
        // them turned Reader's copy into Hyper-C whenever ⇪L was still held.
        if isSynthetic { return .passUnmodified }

        let isCapsAlias = keyCode == capsAliasKeyCode
        let now = CFAbsoluteTimeGetCurrent()

        if isCapsAlias, type == .keyDown {
            return map(machine.handle(.capsDown, at: now))
        }
        if isCapsAlias, type == .keyUp {
            return map(machine.handle(.capsUp, at: now))
        }
        if type == .keyDown {
            return map(machine.handle(isAutorepeat ? .otherKeyRepeat : .otherKeyDown, at: now))
        }
        if type == .keyUp {
            return map(machine.handle(.otherKeyUp, at: now))
        }
        return .passUnmodified
    }

    private func map(_ output: CapsLockStateMachine.Output) -> CapsTapVerdict {
        switch output {
        case .consume: return .consume
        case .consumeAndToggleCapsLock: return .consumeAndToggleCapsLock
        case .passUnmodified: return .passUnmodified
        case .passWithCapsChord: return .passWithCapsChord
        }
    }
}

/// The tap callback, at file scope for the same reason as the state above — and
/// this one is load-bearing in a way that is easy to miss. A closure literal
/// written inside the `@MainActor` expander *inherits* main-actor isolation, so
/// converting it to a C function pointer makes the compiler emit a runtime
/// executor check. On the dedicated tap thread that check fails and traps
/// (`swift_task_isCurrentExecutorWithFlags` → SIGTRAP) on the first keystroke.
/// A file-scope function has no enclosing actor to inherit, so no check is
/// emitted. Keep it here; do not inline it back into the class.
private func capsTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let state = Unmanaged<CapsTapState>.fromOpaque(userInfo).takeUnretainedValue()
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

    switch state.verdict(
        type: type,
        keyCode: keyCode,
        isSynthetic: SyntheticEventMarker.isPlumaEvent(event),
        isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    ) {
    case .consume:
        return nil
    case .consumeAndToggleCapsLock:
        // Never do IOKit on the tap thread — hop to a serial queue.
        capsLockIOQueue.async { CapsLockState.toggle() }
        return nil
    case .passUnmodified:
        return Unmanaged.passUnretained(event)
    case .passWithCapsChord:
        event.flags.formUnion(state.currentCapsFlags())
        return Unmanaged.passUnretained(event)
    }
}

/// Turns Caps Lock into Pluma's shortcut modifier without Hyperkey.
///
/// Layer 1: HID remap Caps → F18 (surgical — never wipes other remaps).
/// Layer 2: session CGEventTap on a **dedicated** run-loop thread treats F18
/// as hold-to-modify, ORing the Caps chord (⌃⌥⌘ or ⌃⌥⌘⇧) onto other keys.
/// Layer 3: re-arm on tapDisabled + wake/lock, with machine reset so a lost
/// key-up cannot strand the modifier on every keystroke.
@MainActor
final class CapsLockExpander: ObservableObject {
    static let shared = CapsLockExpander()

    enum Status: Equatable {
        case off
        case active
        case pausedHyperkeyRunning
        case needsPermission
    }

    @Published private(set) var status: Status = .off
    @Published private(set) var lastError: String?

    /// Live Caps-hold state for release-waiters (see `CapsTapState.isCapsHeld`).
    var isCapsChordHeld: Bool { tapState.isCapsHeld() }

    nonisolated static let hyperAppBundleIDs = [
        "com.knollsoft.Hyperkey",
        "com.knollsoft.Superkey"
    ]

    private let tapState = CapsTapState()
    private let defaults: UserDefaults
    private var pollTask: Task<Void, Never>?
    private var remapApplied = false
    private var activityToken: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var tapThread: Thread?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func startMonitoring() {
        guard pollTask == nil else { return }
        installLifecycleObservers()
        reevaluate()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.reevaluate() }
            }
        }
    }

    func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
        removeLifecycleObservers()
        stopTapAndClearRemap()
        status = .off
    }

    /// Manual recovery: clear our Caps→F18 mapping and turn Caps Lock off.
    func restoreCapsLock() {
        Preferences.setCapsShortcutsEnabled(false, to: defaults)
        stopTapAndClearRemap()
        status = .off
        lastError = nil
        NotificationCenter.default.post(name: .capsShortcutsSettingsDidChange, object: self)
    }

    func reevaluate() {
        let enabled = Preferences.capsShortcutsEnabled(from: defaults)
        let hyperRunning = Self.hyperAppBundleIDs.contains {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
        }

        tapState.lock.lock()
        tapState.capsFlags = Self.cgFlags(
            includesShift: Preferences.capsChordIncludesShift(from: defaults)
        )
        tapState.lock.unlock()
        tapState.configure(
            tapToggles: Preferences.capsTapTogglesCapsLock(from: defaults),
            threshold: Preferences.capsTapThreshold(from: defaults)
        )

        // Abandon a stranded hold on every poll tick (max-hold ceiling only).
        tapState.abandonStrandedHold()

        guard enabled else {
            // If a prior crash left our mapping while the feature is off, remove
            // only our entry — never wipe the user's other remaps.
            if CapsLockHIDRemap.isOurMappingPresent() {
                try? CapsLockHIDRemap.clearOurMapping()
                CapsLockState.turnOff()
                remapApplied = false
            }
            stopTapAndClearRemap()
            status = .off
            lastError = nil
            return
        }

        if hyperRunning {
            stopTapAndClearRemap()
            status = .pausedHyperkeyRunning
            lastError = nil
            return
        }

        do {
            // Tap first: a failed tap must not leave Caps aliased to a dead key.
            try startTap()
            // The system disables a tap whose callback ever runs long. It hands
            // the callback a disable event, which we re-enable from — but this
            // catches the case where that notice was missed, so a dead tap can
            // only last one tick instead of until the next keypress.
            reenableTapIfDisabled()
            try ensureRemap()
            beginActivityAssertion()
            status = .active
            lastError = nil
        } catch {
            stopTapAndClearRemap()
            let wasBlocked = status == .needsPermission
            status = .needsPermission
            lastError = error.localizedDescription
            if !wasBlocked {
                DebugLog.log("caps expander: \(error.localizedDescription)")
            }
        }
    }

    /// Call after Settings toggles so hotkey controllers can re-register.
    func applySettingsChange() {
        Preferences.syncCapsChordShortcuts(to: defaults)
        reevaluate()
        NotificationCenter.default.post(name: .capsShortcutsSettingsDidChange, object: self)
    }

    // MARK: - Staying awake and enabled

    /// App Nap throttles a backgrounded app's threads, and a throttled tap
    /// callback runs long enough for the system to disable the tap — which is
    /// felt as "the first Caps hold after a while does nothing, the second
    /// works," because the keystroke that triggered the disable is dropped.
    /// The assertion keeps the tap thread scheduled normally while still
    /// allowing the machine to sleep on idle.
    private func beginActivityAssertion() {
        guard activityToken == nil else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Caps Lock shortcut event tap"
        )
        DebugLog.log("caps expander: App Nap assertion held")
    }

    private func endActivityAssertion() {
        guard let activityToken else { return }
        ProcessInfo.processInfo.endActivity(activityToken)
        self.activityToken = nil
        DebugLog.log("caps expander: App Nap assertion released")
    }

    private func reenableTapIfDisabled() {
        tapState.lock.lock()
        let tap = tapState.tap
        tapState.lock.unlock()
        guard let tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        tapState.forceReleaseHold()
        DebugLog.log("caps expander: tap was disabled — re-enabled from poll")
    }

    // MARK: - Remap

    private func ensureRemap() throws {
        if remapApplied, CapsLockHIDRemap.isOurMappingPresent(), CapsLockGuardian.isArmed { return }
        let restoreJSON = try CapsLockHIDRemap.apply()
        // Arm before we can possibly crash with the remap live.
        CapsLockGuardian.arm(restoreJSON: restoreJSON)
        remapApplied = true
        DebugLog.log("caps expander: HID Caps→F18 applied")
    }

    private func clearRemapIfNeeded() {
        // Retire the guardian first so its snapshot cannot race our own restore.
        CapsLockGuardian.disarm()
        // Always probe the world — in-memory remapApplied can lie after a crash
        // recovery or a failed ensureRemap that still wrote.
        let present = CapsLockHIDRemap.isOurMappingPresent()
        guard remapApplied || present else { return }
        do {
            try CapsLockHIDRemap.clearOurMapping()
            DebugLog.log("caps expander: HID Caps mapping cleared")
        } catch {
            DebugLog.log("caps expander: failed to clear HID mapping: \(error.localizedDescription)")
        }
        remapApplied = false
        CapsLockState.turnOff()
    }

    // MARK: - Tap (dedicated thread)

    private func startTap() throws {
        tapState.lock.lock()
        let existing = tapState.tap
        let existingValid = existing.map { CFMachPortIsValid($0) } ?? false
        tapState.lock.unlock()

        if existingValid { return }

        // Stale port — tear down before recreating.
        if existing != nil {
            stopTapOnly()
        }

        tapState.lock.lock()
        tapState.machine = CapsLockStateMachine()
        tapState.machine.tapTogglesCapsLock = Preferences.capsTapTogglesCapsLock(from: defaults)
        tapState.machine.tapThreshold = Preferences.capsTapThreshold(from: defaults)
        tapState.lock.unlock()

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        let userInfo = Unmanaged.passUnretained(tapState).toOpaque()
        guard
            let tap = CGEvent.tapCreate(
                // Session tap: Accessibility only (Hyperkey's level). HID-level
                // taps require Input Monitoring.
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: capsTapCallback,
                userInfo: userInfo
            )
        else {
            throw CapsLockExpanderError.tapCreateFailed
        }

        guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            CFMachPortInvalidate(tap)
            throw CapsLockExpanderError.tapCreateFailed
        }
        let started = startTapThread(tap: tap, source: source)
        guard started else {
            CFMachPortInvalidate(tap)
            throw CapsLockExpanderError.tapCreateFailed
        }

        tapState.lock.lock()
        tapState.tap = tap
        tapState.lock.unlock()
        DebugLog.log("caps expander: session tap active (dedicated thread)")
    }

    private func startTapThread(tap: CFMachPort, source: CFRunLoopSource) -> Bool {
        final class ReadyBox: @unchecked Sendable {
            let lock = NSLock()
            var ready = false
            var runLoop: CFRunLoop?
        }
        let box = ReadyBox()

        let thread = Thread {
            let rl = CFRunLoopGetCurrent()
            CFRunLoopAddSource(rl, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            box.lock.lock()
            box.runLoop = rl
            box.ready = true
            box.lock.unlock()
            CFRunLoopRun()
            CFRunLoopRemoveSource(rl, source, .commonModes)
        }
        thread.name = "pluma.caps-event-tap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()

        // Wait briefly for the thread to publish its run loop.
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            box.lock.lock()
            let isReady = box.ready
            let rl = box.runLoop
            box.lock.unlock()
            if isReady {
                tapState.lock.lock()
                tapState.runLoop = rl
                tapState.lock.unlock()
                return true
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return false
    }

    private func stopTapOnly() {
        tapState.lock.lock()
        let tap = tapState.tap
        let rl = tapState.runLoop
        tapState.tap = nil
        tapState.runLoop = nil
        tapState.machine = CapsLockStateMachine()
        tapState.lock.unlock()

        if let rl {
            CFRunLoopStop(rl)
        }
        if let tap, CFMachPortIsValid(tap) {
            CFMachPortInvalidate(tap)
        }
        tapThread = nil
    }

    private func stopTapAndClearRemap() {
        stopTapOnly()
        clearRemapIfNeeded()
        endActivityAssertion()
    }

    // MARK: - Lifecycle re-arm (wake / lock)

    private func installLifecycleObservers() {
        guard workspaceObservers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let wake: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.tapState.forceReleaseHold()
                self?.reevaluate()
            }
        }
        // On lock: clear remap so Caps works at the login/lock UI; re-apply on unlock.
        let onLock: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.tapState.forceReleaseHold()
                self?.stopTapAndClearRemap()
            }
        }
        workspaceObservers = [
            workspace.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: wake
            ),
            workspace.addObserver(
                forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: wake
            )
        ]

        let dnc = DistributedNotificationCenter.default()
        let unlock = Notification.Name("com.apple.screenIsUnlocked")
        let lock = Notification.Name("com.apple.screenIsLocked")
        distributedObservers = [
            dnc.addObserver(forName: unlock, object: nil, queue: .main, using: wake),
            dnc.addObserver(forName: lock, object: nil, queue: .main, using: onLock)
        ]
    }

    private func removeLifecycleObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            workspace.removeObserver(observer)
        }
        workspaceObservers = []
        let dnc = DistributedNotificationCenter.default()
        for observer in distributedObservers {
            dnc.removeObserver(observer)
        }
        distributedObservers = []
    }

    nonisolated static func cgFlags(includesShift: Bool) -> CGEventFlags {
        var flags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
        if includesShift {
            flags.insert(.maskShift)
        }
        return flags
    }
}

enum CapsLockExpanderError: Error, LocalizedError {
    case tapCreateFailed

    var errorDescription: String? {
        switch self {
        case .tapCreateFailed:
            "Couldn't create the Caps Lock event tap. Grant Accessibility for pluma in System Settings."
        }
    }
}
