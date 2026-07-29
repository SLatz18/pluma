# Add optional Input Monitoring for a more reliable clipboard hotkey

Suggested labels: `enhancement`, `macos`, `permissions`

## Summary

Keep Carbon `RegisterEventHotKey` as the zero-permission default for the
clipboard fallback, but optionally add a listen-only `CGEventTap` when the user
grants Input Monitoring.

Some custom, browser, terminal, and Electron applications can consume a key
before Carbon dispatches the registered hotkey. A session event tap sees the
key earlier and makes the fixed clipboard fallback chord more reliable.

## Value relative to `main`

This is the most optional item in the set.

`main` already requires Accessibility for its primary cross-app features and
uses Carbon for configurable rewrite/dictation shortcuts. Input Monitoring is a
separate TCC permission, so requesting it adds onboarding friction.

The enhanced listener should therefore:

- Apply only to the clipboard fallback.
- Be opt-in.
- Never block the standard Carbon path.
- Not claim to improve `main`'s existing configurable shortcuts unless those
  are explicitly migrated in a separate project.

## Reference implementation

Available on branch `cloudai/finish-rewrite-e2e-5d52`:

- `Rewrite/Services/InputMonitoringHotkey.swift`
- `Rewrite/Services/ClipboardHotkeyManager.swift`
- `Rewrite/Services/HotkeyDebouncer.swift`
- `Rewrite/Services/GlobalHotkey.swift`

## Event tap implementation

Use a listen-only session event tap and preserve the original event:

```swift
final class InputMonitoringHotkey: @unchecked Sendable {
    static let shared = InputMonitoringHotkey()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: (@MainActor () -> Void)?

    func start(handler: @escaping @MainActor () -> Void) {
        stop()
        self.handler = handler

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(
                CFRunLoopGetMain(),
                runLoopSource,
                .commonModes
            )
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private static let callback: CGEventTapCallBack = {
        _, type, event, userInfo in
        guard type == .keyDown, let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let listener = Unmanaged<InputMonitoringHotkey>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        guard listener.matches(event) else {
            return Unmanaged.passUnretained(event)
        }

        Task { @MainActor in listener.handler?() }
        return Unmanaged.passUnretained(event)
    }

    private func matches(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.keyboardEventKeycode)
                == Int64(kVK_ANSI_E)
        else {
            return false
        }

        let required: CGEventFlags = [
            .maskControl,
            .maskAlternate,
            .maskShift,
            .maskCommand
        ]
        return event.flags.intersection(required) == required
    }
}
```

## Tier manager

Expose three states:

- `unavailable`: Carbon registration failed.
- `carbonOnly`: zero-permission listener is active.
- `enhanced`: Carbon and Input Monitoring listeners are active.

```swift
func refresh() {
    guard let action else { return }

    let carbonRegistered = GlobalHotkey.shared.register {
        self.fire(action)
    }
    guard carbonRegistered else {
        InputMonitoringHotkey.shared.stop()
        status = .unavailable
        return
    }

    if CGPreflightListenEventAccess() {
        InputMonitoringHotkey.shared.start {
            self.fire(action)
        }
        status = InputMonitoringHotkey.shared.isActive
            ? .enhanced
            : .carbonOnly
    } else {
        InputMonitoringHotkey.shared.stop()
        status = .carbonOnly
    }
}
```

Use `CGRequestListenEventAccess()` only after an explicit user action, then
open:

```text
x-apple.systempreferences:
com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent
```

## Duplicate-event protection

When enhanced mode is active, both Carbon and the event tap can fire. Route
both through a short debouncer:

```swift
struct HotkeyDebouncer {
    private var lastFire: Date?
    let interval: TimeInterval

    mutating func shouldFire() -> Bool {
        let now = Date()
        if let lastFire, now.timeIntervalSince(lastFire) < interval {
            return false
        }
        lastFire = now
        return true
    }
}
```

The reference uses 350 milliseconds.

## Important integration constraints

- Use a distinct Carbon signature/ID from `main`'s `RWRT` shortcut manager.
  The reference uses `RWCB`, ID `100`.
- The Carbon event handler must inspect the received `EventHotKeyID`; it must
  not respond to every hotkey event in the application.
- Install the Carbon event handler once. Re-registering after app activation
  must not accumulate callback handlers.
- Use `.listenOnly`; this feature must not swallow or mutate keyboard events.
- Recheck permission when Rewrite becomes active after a Settings round trip.
- Stop and remove the event tap/run-loop source on termination.
- Do not request Accessibility as a substitute for Input Monitoring.

## Acceptance criteria

- Clipboard hotkey works through Carbon without Input Monitoring.
- Permission is requested only from an explicit Settings button.
- After approval, the tier changes to Enhanced when the app becomes active.
- Apps that consume the Carbon shortcut still trigger the enhanced listener.
- One physical key press starts exactly one rewrite.
- Existing rewrite and dictation hotkeys continue to work.
- Denial leaves the standard Carbon fallback operational.
- Revoking permission downgrades gracefully on the next refresh.

## Tests

- Debouncer accepts the first fire and rejects an immediate duplicate.
- Tier metadata displays correct title/detail/symbol.
- Manual test with permission allowed, denied, and later revoked.
- Manual regression test for Caps Lock E and Caps Lock Space.

## Product decision

Before implementation, confirm that reliability in problematic editors is
worth an additional system permission. If not, ship the Carbon-only clipboard
fallback and omit this issue.
