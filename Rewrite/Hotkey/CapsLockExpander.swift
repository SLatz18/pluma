import AppKit
import Carbon.HIToolbox

// Expands Caps Lock into Rewrite's hyper chord (⌃⌥⌘) at the window-server
// level, so ⇪E / ⇪Space reach the ordinary Carbon hotkey registrations
// without Hyperkey running. The decision logic lives in CapsLockStateMachine;
// this class is the plumbing: tap lifecycle, event translation, reinjection,
// and pausing while a dedicated hyper app (Hyperkey, Superkey) is running —
// two expanders fighting over the same key would double-transform it.
@MainActor
final class CapsLockExpander: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var hyperAppRunning = false

    nonisolated static let hyperAppBundleIDs = [
        "com.knollsoft.Hyperkey",
        "com.knollsoft.Superkey"
    ]

    // The hyper flags match what Hyperkey ships by default (and what our
    // factory shortcuts register): ⌃⌥⌘, Shift notably absent.
    nonisolated static let hyperFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]

    enum TapVerdict: Sendable {
        case consume
        case passUnmodified
        case passWithHyper
    }

    // Everything the C callback reaches, held outside any actor. The callback
    // fires serially on the tap's run loop, and the lock also covers the main
    // actor starting and stopping the tap. An NSLock — not
    // MainActor.assumeIsolated — because Swift 6's region analysis
    // (SendNonSendable) miscompiles the assumeIsolated shape in a tap
    // callback; the lock is the honest primitive for C-callback code anyway.
    final class TapState: @unchecked Sendable {
        let lock = NSLock()
        var machine = CapsLockStateMachine()
        var tap: CFMachPort?

        func verdict(
            type: CGEventType,
            keyCode: Int64,
            alphaShift: Bool
        ) -> TapVerdict {
            lock.lock()
            defer { lock.unlock() }

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                    DebugLog.log("capslock expander: re-enabled after system disabled it")
                }
                return .passUnmodified
            }

            let expanderEvent: ExpanderEvent
            if type == .flagsChanged, keyCode == kVK_CapsLock {
                // For Caps Lock the alphaShift flag reflects the press: set on
                // the way down, clear on the way up.
                expanderEvent = alphaShift ? .capsDown : .capsUp
            } else if type == .keyDown || type == .keyUp {
                expanderEvent = .otherKey
            } else {
                return .passUnmodified
            }

            switch machine.handle(expanderEvent) {
            case .consume:
                return .consume
            case .passUnmodified:
                return .passUnmodified
            case .passWithHyper:
                return .passWithHyper
            }
        }
    }

    private let tapState = TapState()
    private let defaults: UserDefaults
    private var runLoopSource: CFRunLoopSource?
    private var pollTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func startMonitoring() {
        guard pollTask == nil else { return }
        reevaluate()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.reevaluate()
            }
        }
    }

    func reevaluate() {
        hyperAppRunning = Self.hyperAppBundleIDs.contains {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
        }
        let shouldRun = Preferences.capsLockExpanderEnabled(from: defaults) && !hyperAppRunning
        if shouldRun {
            startTap()
        } else {
            stopTap()
        }
    }

    // MARK: Tap lifecycle

    private func startTap() {
        tapState.lock.lock()
        let alreadyRunning = tapState.tap != nil
        tapState.lock.unlock()
        guard !alreadyRunning else { return }

        tapState.lock.lock()
        tapState.machine = CapsLockStateMachine()
        tapState.lock.unlock()

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        let userInfo = Unmanaged.passUnretained(tapState).toOpaque()
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let state = Unmanaged<CapsLockExpander.TapState>
                        .fromOpaque(userInfo).takeUnretainedValue()
                    let verdict = state.verdict(
                        type: type,
                        keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                        alphaShift: event.flags.contains(.maskAlphaShift)
                    )
                    switch verdict {
                    case .consume:
                        return nil
                    case .passUnmodified:
                        return Unmanaged.passUnretained(event)
                    case .passWithHyper:
                        event.flags.formUnion(CapsLockExpander.hyperFlags)
                        return Unmanaged.passUnretained(event)
                    }
                },
                userInfo: userInfo
            )
        else {
            DebugLog.log("capslock expander: tapCreate failed (Accessibility missing?)")
            return
        }

        tapState.lock.lock()
        tapState.tap = tap
        tapState.lock.unlock()

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isActive = true
        DebugLog.log("capslock expander: active")
    }

    private func stopTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil

        tapState.lock.lock()
        let tap = tapState.tap
        tapState.tap = nil
        tapState.lock.unlock()
        if let tap {
            CFMachPortInvalidate(tap)
        }

        if isActive {
            isActive = false
            DebugLog.log("capslock expander: stopped")
        }
    }
}
