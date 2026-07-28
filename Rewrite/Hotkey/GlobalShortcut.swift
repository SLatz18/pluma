import AppKit
import Carbon.HIToolbox

struct GlobalShortcut: Equatable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    static let `default` = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_E),
        carbonModifiers: UInt32(cmdKey | shiftKey),
        display: "⇧⌘E"
    )

    init(keyCode: UInt32, carbonModifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.display = display
    }

    init?(event: NSEvent) {
        guard
            event.type == .keyDown,
            let characters = event.charactersIgnoringModifiers?.uppercased(),
            !characters.isEmpty
        else { return nil }

        var carbon: UInt32 = 0
        var symbols = ""
        if event.modifierFlags.contains(.control) {
            carbon |= UInt32(controlKey)
            symbols += "⌃"
        }
        if event.modifierFlags.contains(.option) {
            carbon |= UInt32(optionKey)
            symbols += "⌥"
        }
        if event.modifierFlags.contains(.shift) {
            carbon |= UInt32(shiftKey)
            symbols += "⇧"
        }
        if event.modifierFlags.contains(.command) {
            carbon |= UInt32(cmdKey)
            symbols += "⌘"
        }
        guard carbon != 0 else { return nil }

        keyCode = UInt32(event.keyCode)
        carbonModifiers = carbon
        display = symbols + characters
    }
}
