import AppKit
import Carbon.HIToolbox

@MainActor
final class HotkeyManager {
    enum Slot: UInt32 {
        case rewriteSelection = 1
        case dictation = 2
        // The clipboard fallback for apps where Accessibility insertion does not
        // work (Google Docs, Electron): copy, press, paste. Issue #12.
        case clipboardRewrite = 3
        // Speak the selection (or the clipboard if nothing is selected).
        case readSelection = 4
        // Push-to-talk like dictation, but the utterance is an *intent* — the
        // reply is drafted from the visible conversation and inserted.
        case draftReply = 5
    }

    var onPress: ((Slot) -> Void)?
    var onRelease: ((Slot) -> Void)?

    private var hotKeyRefs: [Slot: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?

    private static let signature = OSType(0x52575254) // 'RWRT'

    func register(_ shortcut: GlobalShortcut, in slot: Slot) {
        unregisterHotKey(slot)

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: slot.rawValue)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        DebugLog.log("hotkey register \(shortcut.display) slot=\(slot.rawValue): status \(status)")
        guard status == noErr, let ref else { return }
        hotKeyRefs[slot] = ref

        installHandlerIfNeeded()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }

        // Both kinds go through one handler; the hotkey ID distinguishes which
        // shortcut fired, and press vs. release drives push-to-talk.
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else {
                    return OSStatus(eventNotHandledErr)
                }
                let manager = Unmanaged<HotkeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

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
                    hotKeyID.signature == HotkeyManager.signature,
                    let slot = Slot(rawValue: hotKeyID.id)
                else {
                    return OSStatus(eventNotHandledErr)
                }

                let isRelease = GetEventKind(event) == UInt32(kEventHotKeyReleased)
                return MainActor.assumeIsolated {
                    // Handlers are installed per instance on the shared
                    // dispatcher target, so every instance sees every hotkey.
                    // Only act on slots this instance actually registered.
                    guard manager.hotKeyRefs[slot] != nil else {
                        return OSStatus(eventNotHandledErr)
                    }
                    manager.dispatch(slot: slot, isRelease: isRelease)
                    return noErr
                }
            },
            2,
            &eventTypes,
            selfPointer,
            &handlerRef
        )
    }

    private func dispatch(slot: Slot, isRelease: Bool) {
        if isRelease {
            onRelease?(slot)
        } else {
            onPress?(slot)
        }
    }

    func unregisterHotKey(_ slot: Slot) {
        if let ref = hotKeyRefs[slot] {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs[slot] = nil
    }
}
