import AppKit
import Carbon.HIToolbox

@MainActor
final class HotkeyManager {
    var onHotKey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private static let signature = OSType(0x52575254) // 'RWRT'

    func register(_ shortcut: GlobalShortcut) {
        unregisterHotKey()

        var hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        DebugLog.log("hotkey register \(shortcut.display): status \(status)")
        guard status == noErr else { return }
        hotKeyRef = ref

        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else {
                    return OSStatus(eventNotHandledErr)
                }
                let manager = Unmanaged<HotkeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                MainActor.assumeIsolated {
                    manager.onHotKey?()
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &handlerRef
        )
    }

    func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }
}
