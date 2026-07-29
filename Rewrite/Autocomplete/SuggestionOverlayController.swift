import AppKit

// Pure-AppKit pill: the previous SwiftUI hosting view re-entered
// setNeedsUpdateConstraints during display-cycle layout and crashed the app
// (twice), so the overlay avoids a SwiftUI graph entirely.
private final class PillView: NSVisualEffectView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "⇥")
    private let hintBezel = NSView()
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor

        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.preferredMaxLayoutWidth = 500

        hintLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        hintLabel.textColor = .tertiaryLabelColor
        hintBezel.wantsLayer = true
        hintBezel.layer?.cornerRadius = 3
        hintBezel.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintBezel.addSubview(hintLabel)
        NSLayoutConstraint.activate([
            hintLabel.centerXAnchor.constraint(equalTo: hintBezel.centerXAnchor),
            hintLabel.centerYAnchor.constraint(equalTo: hintBezel.centerYAnchor),
            hintBezel.widthAnchor.constraint(equalTo: hintLabel.widthAnchor, constant: 8),
            hintBezel.heightAnchor.constraint(equalTo: hintLabel.heightAnchor, constant: 2)
        ])

        iconView.contentTintColor = .secondaryLabelColor

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(hintBezel)

        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showSuggestion(_ text: String) {
        stopDictationPulse()
        iconView.isHidden = true
        hintBezel.isHidden = false
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.preferredMaxLayoutWidth = 500
        label.stringValue = text
    }

    func showStatus(systemImage: String, message: String) {
        stopDictationPulse()
        iconView.isHidden = false
        iconView.contentTintColor = .secondaryLabelColor
        let base = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
        iconView.image = base?.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        hintBezel.isHidden = true
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.preferredMaxLayoutWidth = 500
        label.stringValue = message
    }

    func showDictation(transcript: String) {
        iconView.isHidden = false
        iconView.contentTintColor = .systemRed
        let base = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")
        iconView.image = base?.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        startDictationPulse()
        hintBezel.isHidden = true
        if transcript.isEmpty {
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.maximumNumberOfLines = 1
            label.stringValue = "Listening…"
        } else {
            // Volatile results get revised as more audio arrives, so keep the
            // tail visible rather than the beginning.
            label.font = .systemFont(ofSize: 12)
            label.textColor = .labelColor
            label.maximumNumberOfLines = 2
            label.stringValue = transcript
        }
        label.lineBreakMode = .byTruncatingHead
        label.preferredMaxLayoutWidth = 320
    }

    // A breathing mic stands in for SwiftUI's repeating symbol effect, which
    // has no AppKit equivalent; it stops the moment any other pill mode shows.
    private func startDictationPulse() {
        guard iconView.layer?.animation(forKey: "dictationPulse") == nil else { return }
        iconView.wantsLayer = true
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.35
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        iconView.layer?.add(pulse, forKey: "dictationPulse")
    }

    private func stopDictationPulse() {
        iconView.layer?.removeAnimation(forKey: "dictationPulse")
        iconView.layer?.opacity = 1.0
    }
}

@MainActor
final class SuggestionOverlayController {
    // One panel is shared by autocomplete, selection rewrite, and dictation.
    // Shows always preempt (last writer wins), but a hide only lands if the
    // current presentation belongs to the caller — so a delayed hide (e.g. a
    // status flash's 2.5 s timer) can't kill a newer presentation.
    enum Owner {
        case autocomplete, rewrite, dictation
    }

    private var panel: NSPanel?
    private var pill: PillView?
    private var currentOwner: Owner?

    var isVisible: Bool { panel?.isVisible ?? false }

    // NSEvent.mouseLocation is Cocoa bottom-left-origin; AX/overlay coordinates
    // are top-left-origin on the primary display.
    static func mouseTopLeftPoint() -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? mouse.y
        return CGPoint(x: mouse.x + 8, y: primaryHeight - mouse.y + 12)
    }

    func show(text: String, atTopLeftPoint point: CGPoint, from owner: Owner) {
        currentOwner = owner
        ensurePanel()
        pill?.showSuggestion(text)
        present(at: point)
    }

    func showStatus(systemImage: String, message: String, atTopLeftPoint point: CGPoint, from owner: Owner) {
        currentOwner = owner
        ensurePanel()
        pill?.showStatus(systemImage: systemImage, message: message)
        present(at: point)
    }

    func showDictation(transcript: String, atTopLeftPoint point: CGPoint, from owner: Owner) {
        currentOwner = owner
        ensurePanel()
        pill?.showDictation(transcript: transcript)
        present(at: point)
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let pill = PillView(frame: .zero)
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
        panel.contentView = pill
        self.panel = panel
        self.pill = pill
    }

    // Deferred one run loop turn so window mutations never land inside an
    // in-flight display cycle.
    private func present(at point: CGPoint) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel, let pill else { return }
            pill.layoutSubtreeIfNeeded()
            let fitting = pill.fittingSize
            panel.setContentSize(fitting)
            panel.setFrameOrigin(cocoaOrigin(forTopLeftPoint: point, panelHeight: fitting.height))
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        currentOwner = nil
        DispatchQueue.main.async { [weak panel] in
            panel?.orderOut(nil)
        }
    }

    func hide(from owner: Owner) {
        guard currentOwner == owner else { return }
        hide()
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
