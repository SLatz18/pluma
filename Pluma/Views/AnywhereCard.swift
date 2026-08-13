import SwiftUI

/// The bridge from playground to system-wide: the selection-rewrite hotkey,
/// in trigger → action form.
struct AnywhereCard: View {
    @EnvironmentObject private var controller: SelectionRewriteController
    @EnvironmentObject private var model: RewriteViewModel

    @State private var isRecording = false

    var body: some View {
        DSShortcutCard(
            systemImage: "keyboard",
            tint: DS.Feature.shortcut.color,
            eyebrowTrigger: "In any app",
            eyebrowAction: model.chainDisplay,
            title: "Rewrite the selection",
            detail: detail,
            shortcut: controller.shortcut,
            isRecording: $isRecording,
            conflict: controller.shortcutConflict
        ) { shortcut in
            controller.recordShortcut(shortcut)
        }
    }

    private var detail: String {
        if isRecording {
            "Press the new shortcut. Hyperkey chords work too. Esc cancels."
        } else if model.chain.isEmpty {
            "Pick a recipe above to give the shortcut a pipeline."
        } else {
            "Runs your pipeline — built above — on text selected in any app."
        }
    }
}
