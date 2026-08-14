import AppKit
import Carbon.HIToolbox

struct GlobalShortcut: Equatable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    // Factory chords ride Caps Lock: Caps is pluma's one modifier, and the
    // letter picks the verb — E for edit, Space for speech. When Caps shortcuts
    // are enabled, pluma expands Caps into ⌃⌥⌘ (or ⌃⌥⌘⇧ if the user opts in).
    // Without that, Hyperkey (or a recorded chord) can still deliver the same
    // modifiers. Both three- and four-modifier Caps chords count as the same
    // physical press for display and conflict checks.
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

    // L for listen. Distinct from ⇪E / ⇪Space / ⇪R so all four factory chords
    // can be bound at once.
    static let readerDefault = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_L),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
        display: "⇪L"
    )

    // Draft-a-reply is push-to-talk like dictation, so it rides the same Caps
    // Lock modifier: D for "draft". Hold it, speak the intent, release.
    static let draftReplyDefault = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_D),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
        display: "⇪D"
    )

    static let capsChords: Set<UInt32> = [
        UInt32(controlKey | optionKey | cmdKey),
        UInt32(controlKey | optionKey | shiftKey | cmdKey)
    ]

    static func capsChordModifiers(includesShift: Bool) -> UInt32 {
        var modifiers = UInt32(controlKey | optionKey | cmdKey)
        if includesShift {
            modifiers |= UInt32(shiftKey)
        }
        return modifiers
    }

    var isCapsChord: Bool {
        Self.capsChords.contains(carbonModifiers)
    }

    /// When the Caps chord with/without Shift setting flips, rewrite stored
    /// Caps chords to the active modifier set. Custom non-Caps shortcuts pass through.
    func aligningCapsChord(includesShift: Bool) -> GlobalShortcut {
        guard isCapsChord else { return self }
        return GlobalShortcut(
            keyCode: keyCode,
            carbonModifiers: Self.capsChordModifiers(includesShift: includesShift),
            display: display
        )
    }

    init(keyCode: UInt32, carbonModifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.display = display
    }

    // Carbon refuses to register the same chord twice in one process, so two
    // features on the same chord would leave one silently dead. Caps three-
    // and four-modifier variants are the same physical press.
    func conflicts(with other: GlobalShortcut) -> Bool {
        guard keyCode == other.keyCode else { return false }
        if carbonModifiers == other.carbonModifiers { return true }
        return Self.capsChords.contains(carbonModifiers)
            && Self.capsChords.contains(other.carbonModifiers)
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
        // A full Caps chord almost certainly came from Caps Lock; showing
        // "⇪E" beats glyphs for modifiers the user never pressed.
        let keyName = characters == " " ? "Space" : characters
        display = (Self.capsChords.contains(carbon) ? "⇪" : symbols) + keyName
    }
}
