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

    // Hyperkey expands Caps Lock into a modifier chord before any app sees the
    // event, so this is what "Caps Lock R" arrives as. It ships ⌃⌥⌘ (its
    // hyperFlags default of 0x1C0000) and notably leaves Shift out, though it
    // is configurable — so both the three- and four-modifier chords are
    // treated as Caps Lock when deciding how to draw a shortcut.
    static let dictationDefault = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_R),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
        display: "⇪R"
    )

    private static let hyperChords: Set<UInt32> = [
        UInt32(controlKey | optionKey | cmdKey),
        UInt32(controlKey | optionKey | shiftKey | cmdKey)
    ]

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
        // A full hyper chord almost certainly came from Caps Lock via Hyperkey;
        // showing "⇪R" beats glyphs for modifiers the user never pressed.
        display = (Self.hyperChords.contains(carbon) ? "⇪" : symbols) + characters
    }
}
