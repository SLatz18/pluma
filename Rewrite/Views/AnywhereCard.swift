import SwiftUI

/// The bridge from playground to system-wide: the selection-rewrite hotkey,
/// in trigger → action form.
struct AnywhereCard: View {
    @EnvironmentObject private var controller: SelectionRewriteController
    @EnvironmentObject private var model: RewriteViewModel

    @State private var isRecording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                DSIconTile(systemImage: "keyboard", tint: DS.Feature.shortcut.color)

                VStack(alignment: .leading, spacing: 4) {
                    DSEyebrow(trigger: "In any app", action: model.chainDisplay)

                    Text("Rewrite the selection")
                        .font(DS.cardTitle)

                    Text(
                        isRecording
                            ? "Press the new shortcut. Hyperkey chords work too. Esc cancels."
                            : model.chain.isEmpty
                                ? "Pick a recipe above to give the shortcut a pipeline."
                                : "Runs your pipeline — built above — on text selected in any app."
                    )
                        .font(DS.meta)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                ShortcutRecorderView(
                    shortcut: controller.shortcut,
                    isRecording: $isRecording
                ) { shortcut in
                    controller.recordShortcut(shortcut)
                }
            }

            if let conflict = controller.shortcutConflict {
                Label(conflict, systemImage: "exclamationmark.triangle.fill")
                    .font(DS.meta)
                    .foregroundStyle(.orange)
            }
        }
        .dsCard()
    }
}
