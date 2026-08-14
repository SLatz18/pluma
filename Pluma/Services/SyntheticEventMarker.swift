import CoreGraphics

/// Pluma posts synthetic keyboard events: ⌘C to copy a selection for Reader,
/// ⌘V to paste dictation into fields that ignore AX writes. Its own event tap
/// and global monitors must recognize those events and leave them alone — the
/// Caps expander must not OR the Caps chord onto them (which turned Reader's
/// ⌘C into a Hyper-C while the ⇪L chord was still held), and the dictation
/// edit monitor must not treat them as user edits (which wiped the spacing
/// memory right after every paste-fallback insertion).
enum SyntheticEventMarker {
    /// "PLMA" — arbitrary but stable magic stamped into eventSourceUserData.
    /// Hardware events carry 0 there, so a match can only be one of ours.
    static let signature: Int64 = 0x504C_4D41

    static func mark(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: signature)
    }

    static func isPlumaEvent(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == signature
    }
}
