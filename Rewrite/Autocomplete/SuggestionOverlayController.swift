import AppKit
import SwiftUI

struct SuggestionOverlayView: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("⇥")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    Color.primary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 3)
                )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        }
    }
}

@MainActor
final class SuggestionOverlayController {
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(text: String, atTopLeftPoint point: CGPoint) {
        let hosting = NSHostingView(rootView: SuggestionOverlayView(text: text))
        hosting.layout()
        let fitting = hosting.fittingSize

        let panel: NSPanel
        if let existing = self.panel {
            panel = existing
            panel.contentView = hosting
        } else {
            panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.ignoresMouseEvents = true
            panel.contentView = hosting
            self.panel = panel
        }

        panel.setContentSize(fitting)
        panel.setFrameOrigin(cocoaOrigin(forTopLeftPoint: point, panelHeight: fitting.height))
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // AX coordinates are top-left-origin relative to the primary display;
    // Cocoa window origins are bottom-left-origin on that same display.
    private func cocoaOrigin(forTopLeftPoint point: CGPoint, panelHeight: CGFloat) -> CGPoint {
        guard let primary = NSScreen.screens.first else { return point }
        return CGPoint(
            x: point.x,
            y: primary.frame.height - point.y - panelHeight
        )
    }
}
