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
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?
    private(set) var isRegistered = false
    private static let signature: OSType = 0x52574342 // 'RWCB'
    private static let identifier: UInt32 = 100

    private init() {}

    /// Registers Control-Option-Shift-Command-E (hyperkey + E).
    @discardableResult
    func register(action: @escaping () -> Void) -> Bool {
        unregister()
        self.action = action
        isRegistered = false

        installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: Self.identifier
        )
        let modifiers = UInt32(controlKey | optionKey | shiftKey | cmdKey)

        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_E),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        isRegistered = status == noErr
        return isRegistered
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard
                    status == noErr,
                    hotKeyID.signature == GlobalHotkey.signature,
                    hotKeyID.id == GlobalHotkey.identifier
                else {
                    return OSStatus(eventNotHandledErr)
                }

                let hotkey = Unmanaged<GlobalHotkey>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in hotkey.action?() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        action = nil
        isRegistered = false
    }
}
