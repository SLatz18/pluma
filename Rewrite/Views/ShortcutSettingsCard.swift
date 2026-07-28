import SwiftUI

struct ShortcutSettingsCard: View {
    @EnvironmentObject private var controller: SelectionRewriteController

    @State private var isRecording = false
    @State private var keyMonitor: Any?

    var body: some View {
        HStack(spacing: 14) {
            Text(isRecording ? "…" : controller.shortcut.display)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .frame(minHeight: 24)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isRecording ? Color.accentColor : Color.primary.opacity(0.12)
                        )
                }

            VStack(alignment: .leading, spacing: 3) {
                Text("Rewrite selection")
                    .font(.headline)
                Text(
                    isRecording
                        ? "Press the new shortcut. Hyperkey chords work too. Esc cancels."
                        : "Works in any app with Accessibility access. Select text, press the shortcut."
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(isRecording ? "Cancel" : "Change…") {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }
        }
        .padding(16)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .onDisappear {
            stopRecording()
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
