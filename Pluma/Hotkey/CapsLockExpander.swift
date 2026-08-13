import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    /// Posted when Caps shortcut enablement or Caps chord (with/without Shift) changes.
    static let capsShortcutsSettingsDidChange = Notification.Name("pluma.capsShortcutsSettingsDidChange")
}

/// Turns Caps Lock into Pluma's shortcut modifier without Hyperkey.
///
/// Layer 1: HID remap Caps → F18 (kills toggle/LED).
/// Layer 2: session CGEventTap treats F18 as hold-to-modify, ORing the
/// chosen Caps chord (⌃⌥⌘ or ⌃⌥⌘⇧) onto other keys.
/// Layer 3: re-arm on tapDisabled + wake/lock — the reliability Hyperkey lacks.
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

    nonisolated static let hyperAppBundleIDs = [
        "com.knollsoft.Hyperkey",
        "com.knollsoft.Superkey"
    ]

    /// F18 after HID remap — Carbon/Cocoa keycode.
    nonisolated static let capsAliasKeyCode = CGKeyCode(kVK_F18)

    enum TapVerdict: Sendable {
        case consume
        case passUnmodified
        case passWithCapsChord
    }

    final class TapState: @unchecked Sendable {
        let lock = NSLock()
        var machine = CapsLockStateMachine()
        var tap: CFMachPort?
        var capsFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]

        func verdict(type: CGEventType, keyCode: Int64) -> TapVerdict {
            lock.lock()
            defer { lock.unlock() }

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                    DebugLog.log("caps expander: re-enabled after system disabled it")
                }
                return .passUnmodified
            }

            let isCapsAlias = keyCode == Int64(CapsLockExpander.capsAliasKeyCode)
            let event: CapsLockExpanderEvent
            if isCapsAlias, type == .keyDown {
                event = .capsDown
            } else if isCapsAlias, type == .keyUp {
                event = .capsUp
            } else if type == .keyDown || type == .keyUp {
                event = .otherKey
            } else {
                return .passUnmodified
            }

            switch machine.handle(event) {
            case .consume: return .consume
            case .passUnmodified: return .passUnmodified
            case .passWithCapsChord: return .passWithCapsChord
            }
        }
    }

    private let tapState = TapState()
    private let defaults: UserDefaults
    private var runLoopSource: CFRunLoopSource?
    private var pollTask: Task<Void, Never>?
    private var remapApplied = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

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
                self?.reevaluate()
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

        guard enabled else {
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
            try ensureRemap()
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

    // MARK: - Remap

    private func ensureRemap() throws {
        guard !remapApplied else { return }
        try CapsLockHIDRemap.apply()
        remapApplied = true
        DebugLog.log("caps expander: HID Caps→F18 applied")
    }

    private func clearRemapIfNeeded() {
        guard remapApplied else { return }
        do {
            try CapsLockHIDRemap.clear()
            DebugLog.log("caps expander: HID Caps mapping cleared")
        } catch {
            DebugLog.log("caps expander: failed to clear HID mapping: \(error.localizedDescription)")
        }
        remapApplied = false
    }

    // MARK: - Tap

    private func startTap() throws {
        tapState.lock.lock()
        let alreadyRunning = tapState.tap != nil
        tapState.lock.unlock()
        guard !alreadyRunning else { return }

        tapState.lock.lock()
        tapState.machine = CapsLockStateMachine()
        tapState.lock.unlock()

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(tapState).toOpaque()
        guard
            let tap = CGEvent.tapCreate(
                // Session tap, not `.cghidEventTap`: HID-level taps are gated
                // behind Input Monitoring, while a session tap needs only the
                // Accessibility grant Pluma already holds. This is the level
                // Hyperkey works at, and it still sees keys before any app.
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let state = Unmanaged<CapsLockExpander.TapState>
                        .fromOpaque(userInfo).takeUnretainedValue()
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    let verdict = state.verdict(type: type, keyCode: keyCode)
                    switch verdict {
                    case .consume:
                        return nil
                    case .passUnmodified:
                        return Unmanaged.passUnretained(event)
                    case .passWithCapsChord:
                        state.lock.lock()
                        let flags = state.capsFlags
                        state.lock.unlock()
                        event.flags.formUnion(flags)
                        return Unmanaged.passUnretained(event)
                    }
                },
                userInfo: userInfo
            )
        else {
            throw CapsLockExpanderError.tapCreateFailed
        }

        tapState.lock.lock()
        tapState.tap = tap
        tapState.lock.unlock()

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        DebugLog.log("caps expander: HID tap active")
    }

    private func stopTapAndClearRemap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil

        tapState.lock.lock()
        let tap = tapState.tap
        tapState.tap = nil
        tapState.machine = CapsLockStateMachine()
        tapState.lock.unlock()
        if let tap {
            CFMachPortInvalidate(tap)
        }
        clearRemapIfNeeded()
    }

    // MARK: - Lifecycle re-arm (wake / lock)

    private func installLifecycleObservers() {
        guard workspaceObservers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let wake: (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.reevaluate() }
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
            dnc.addObserver(forName: lock, object: nil, queue: .main, using: wake)
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
