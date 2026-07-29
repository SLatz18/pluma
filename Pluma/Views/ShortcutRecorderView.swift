import SwiftUI

/// The badge + Change…/Cancel + key-monitor state machine shared by both
/// shortcut cards. Esc cancels; anything GlobalShortcut accepts is handed
/// back via onRecord. The host owns conflict messaging and explainer copy.
struct ShortcutRecorderView: View {
    let shortcut: GlobalShortcut
    @Binding var isRecording: Bool
    let onRecord: (GlobalShortcut) -> Void

    @State private var keyMonitor: Any?

    var body: some View {
        HStack(spacing: 14) {
            Text(isRecording ? "…" : shortcut.display)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .frame(minHeight: 24)
                .background(
                    DS.insetBackground,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isRecording ? Color.accentColor : DS.hairline)
                }

            Button(isRecording ? "Cancel" : "Change…") {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }
            .controlSize(.small)
        }
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
                onRecord(shortcut)
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
