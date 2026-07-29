import SwiftUI

/// The bridge from playground to system-wide: the selection-rewrite hotkey,
/// in trigger → action form.
struct AnywhereCard: View {
    @EnvironmentObject private var controller: SelectionRewriteController
    @EnvironmentObject private var model: RewriteViewModel

    @State private var isRecording = false
    @State private var keyMonitor: Any?

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

                shortcutBadge

                Button(isRecording ? "Cancel" : "Change…") {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                }
                .controlSize(.small)
            }

            if let conflict = controller.shortcutConflict {
                Label(conflict, systemImage: "exclamationmark.triangle.fill")
                    .font(DS.meta)
                    .foregroundStyle(.orange)
            }
        }
        .dsCard()
        .onDisappear {
            stopRecording()
        }
    }

    private var shortcutBadge: some View {
        Text(isRecording ? "…" : controller.shortcut.display)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .frame(minHeight: 24)
            .background(
                DS.insetBackground,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isRecording ? Color.accentColor : DS.hairline
                    )
            }
    }

    private func startRecording() {
        isRecording = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            if let shortcut = GlobalShortcut(event: event) {
                controller.recordShortcut(shortcut)
                stopRecording()
                return nil
            }
            return nil
        }
    }

    private func stopRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        isRecording = false
    }
}
