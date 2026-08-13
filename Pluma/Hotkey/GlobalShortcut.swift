import AppKit
import Carbon.HIToolbox

struct GlobalShortcut: Equatable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    // Both factory chords ride Caps Lock via Hyperkey: Caps Lock is pluma's
    // one modifier, and the letter picks the verb — E for edit, Space for
    // speech. Hyperkey expands Caps Lock into a modifier chord before any app
    // sees the event, so this is what those presses arrive as. It ships ⌃⌥⌘
    // (its hyperFlags default of 0x1C0000) and notably leaves Shift out,
    // though it is configurable — so both the three- and four-modifier chords
    // are treated as Caps Lock when deciding how to draw a shortcut.
    static let `default` = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_E),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
        display: "⇪E"
    )

    static let dictationDefault = GlobalShortcut(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
        display: "⇪Space"
    )

    // The clipboard fallback rides the same Caps Lock modifier: R for "rewrite
    // what I copied". Distinct from ⇪E so both paths can be bound at once.
    static let clipboardDefault = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_R),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
        display: "⇪R"
    )

    // Draft-a-reply is push-to-talk like dictation, so it rides the same Caps
    // Lock modifier: D for "draft". Hold it, speak the intent, release.
    static let draftReplyDefault = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_D),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
        display: "⇪D"
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

    // Carbon refuses to register the same chord twice in one process, so two
    // features on the same chord would leave one silently dead. Hyperkey's
    // three- and four-modifier variants are the same physical press.
    func conflicts(with other: GlobalShortcut) -> Bool {
        guard keyCode == other.keyCode else { return false }
        if carbonModifiers == other.carbonModifiers { return true }
        return Self.hyperChords.contains(carbonModifiers)
            && Self.hyperChords.contains(other.carbonModifiers)
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
        // showing "⇪E" beats glyphs for modifiers the user never pressed.
        let keyName = characters == " " ? "Space" : characters
        display = (Self.hyperChords.contains(carbon) ? "⇪" : symbols) + keyName
    }
}
