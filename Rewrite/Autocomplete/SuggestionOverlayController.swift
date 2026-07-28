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

struct StatusOverlayView: View {
    let systemImage: String
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        }
    }
}

@MainActor
final class SuggestionOverlayController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?

    var isVisible: Bool { panel?.isVisible ?? false }

    // NSEvent.mouseLocation is Cocoa bottom-left-origin; AX/overlay coordinates
    // are top-left-origin on the primary display.
    static func mouseTopLeftPoint() -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? mouse.y
        return CGPoint(x: mouse.x + 8, y: primaryHeight - mouse.y + 12)
    }

    func show(text: String, atTopLeftPoint point: CGPoint) {
        show(content: SuggestionOverlayView(text: text), atTopLeftPoint: point)
    }

    func show<Content: View>(content: Content, atTopLeftPoint point: CGPoint) {
        let view = AnyView(content)
        if let hostingView {
            hostingView.rootView = view
        } else {
            let hosting = NSHostingView(rootView: view)
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [
                .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary
            ]
            panel.ignoresMouseEvents = true
            panel.contentView = hosting
            self.panel = panel
            self.hostingView = hosting
        }

        // Mutating the window inside an in-flight display cycle makes SwiftUI
        // re-enter setNeedsUpdateConstraints and AppKit throws; defer to the
        // next run loop turn.
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel, let hostingView else { return }
            hostingView.layoutSubtreeIfNeeded()
            let fitting = hostingView.fittingSize
            panel.setContentSize(fitting)
            panel.setFrameOrigin(cocoaOrigin(forTopLeftPoint: point, panelHeight: fitting.height))
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        DispatchQueue.main.async { [weak panel] in
            panel?.orderOut(nil)
        }
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
