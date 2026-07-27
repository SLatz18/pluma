import AppKit
import Carbon.HIToolbox

/// Registers a system-wide hotkey via Carbon's RegisterEventHotKey.
/// This API is allowed inside the App Sandbox and needs no Accessibility
/// permission, unlike CGEvent-based global monitors.
///
/// Note: macOS 15+ requires the chord to include Control or Command.
/// The hyperkey chord (Control-Option-Shift-Command) qualifies.
@MainActor
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    private init() {}

    /// Registers Control-Option-Shift-Command-E (hyperkey + E).
    @discardableResult
    func register(action: @escaping () -> Void) -> Bool {
        unregisterHotKey()
        self.action = action

        if eventHandlerRef == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )

            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { _, _, userData in
                    guard let userData else { return noErr }
                    let hotkey = Unmanaged<GlobalHotkey>
                        .fromOpaque(userData)
                        .takeUnretainedValue()
                    Task { @MainActor in hotkey.action?() }
                    return noErr
                },
                1,
                &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandlerRef
            )

            guard status == noErr else {
                self.action = nil
                return false
            }
        }

        // 'RWRT' signature, id 1
        let hotKeyID = EventHotKeyID(signature: 0x52575254, id: 1)
        let modifiers = UInt32(controlKey | optionKey | shiftKey | cmdKey)

        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_E),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            self.action = nil
        }
        return status == noErr
    }

    func unregister() {
        unregisterHotKey()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        eventHandlerRef = nil
        action = nil
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }
}
