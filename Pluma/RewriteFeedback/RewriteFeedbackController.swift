import AppKit

enum RewriteUndoResult: Equatable, Sendable {
    case restored
    case contentChanged
    case unavailable

    var message: String {
        switch self {
        case .restored: "Original restored"
        case .contentChanged: "Text changed after the rewrite, so Undo was not applied"
        case .unavailable: "Undo is unavailable in this field"
        }
    }

}

private final class RewriteFeedbackPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }
}

private final class ClosureButton: NSButton {
    var handler: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self
        action = #selector(invokeHandler)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func invokeHandler() {
        handler?()
    }
}

private final class RewriteFeedbackView: NSVisualEffectView {
    private let onDismiss: () -> Void

    init(
        original: String,
        revised: String,
        pipeline: String,
        destination: String,
        pasteHint: Bool,
        onUndo: @escaping @MainActor () async -> RewriteUndoResult,
        onDismiss: @escaping () -> Void
    ) {
        self.onDismiss = onDismiss
        super.init(frame: .zero)

        material = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            ? .windowBackground : .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1

        let segments = WordDiffer.diff(original: original, revised: revised)
        let changes = WordDiffer.changeCount(segments)

        let title = NSTextField(labelWithString: "What changed")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .labelColor

        let closeButton = ClosureButton(frame: .zero)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss")
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = "Dismiss"
        closeButton.handler = onDismiss

        let heading = NSStackView(views: [title, NSView(), closeButton])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 8

        let recipe = NSTextField(labelWithString: pipeline)
        recipe.font = .systemFont(ofSize: 11, weight: .medium)
        recipe.textColor = .secondaryLabelColor
        recipe.lineBreakMode = .byTruncatingTail

        let changeWord = changes == 1 ? "change" : "changes"
        let status = NSTextField(labelWithString: "\(changes) \(changeWord) · \(destination)")
        status.font = .systemFont(ofSize: 11, weight: .semibold)
        status.textColor = .systemGreen

        let diff = NSTextField(wrappingLabelWithString: "")
        diff.attributedStringValue = Self.attributedDiff(segments)
        diff.maximumNumberOfLines = 5
        diff.lineBreakMode = .byTruncatingTail
        diff.preferredMaxLayoutWidth = 376
        diff.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let undoButton = ClosureButton(frame: .zero)
        undoButton.title = "Undo"
        undoButton.bezelStyle = .rounded
        undoButton.controlSize = .small

        let doneButton = ClosureButton(frame: .zero)
        doneButton.title = "Done"
        doneButton.bezelStyle = .rounded
        doneButton.controlSize = .small
        doneButton.keyEquivalent = "\r"
        doneButton.handler = onDismiss

        let hint = NSTextField(labelWithString: pasteHint ? "⌘V to paste" : "")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor

        let footer = NSStackView(views: [hint, NSView(), undoButton, doneButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8

        let content = NSStackView(views: [heading, recipe, status, diff, footer])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 9
        content.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        heading.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        diff.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 408),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            heading.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -32),
            footer.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -32),
            diff.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -32)
        ])

        undoButton.handler = { [weak undoButton, weak doneButton] in
            undoButton?.isEnabled = false
            doneButton?.isEnabled = false
            Task { @MainActor in
                let result = await onUndo()
                if result == .restored {
                    onDismiss()
                } else {
                    status.stringValue = result.message
                    status.textColor = .systemOrange
                    doneButton?.isEnabled = true
                }
            }
        }

        applyDynamicColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyDynamicColors()
    }

    private func applyDynamicColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.65).cgColor
        }
    }

    private static func attributedDiff(_ segments: [DiffSegment]) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let maximumDisplayedSegments = 180
        var displayed = Array(segments.prefix(maximumDisplayedSegments))
        if displayed.count < segments.count {
            displayed.append(DiffSegment(kind: .unchanged, text: "…"))
        }
        for (index, segment) in displayed.enumerated() {
            let text = segment.text + (index == displayed.count - 1 ? "" : " ")
            var attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.labelColor
            ]
            switch segment.kind {
            case .unchanged:
                break
            case .removed:
                attributes[.foregroundColor] = NSColor.systemRed
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            case .added:
                attributes[.foregroundColor] = NSColor.systemGreen
                attributes[.font] = NSFont.systemFont(ofSize: 12, weight: .medium)
            }
            output.append(NSAttributedString(string: text, attributes: attributes))
        }
        return output
    }
}

/// A separate, non-activating card shown only after a successful rewrite. The
/// compact status pill remains responsible for in-flight and error feedback.
@MainActor
final class RewriteFeedbackController {
    private let panel = RewriteFeedbackPanel()
    private var dismissTask: Task<Void, Never>?

    func showResult(
        original: String,
        revised: String,
        pipeline: String,
        destination: String,
        pasteHint: Bool,
        onUndo: @escaping @MainActor () async -> RewriteUndoResult
    ) {
        dismissTask?.cancel()
        let view = RewriteFeedbackView(
            original: original,
            revised: revised,
            pipeline: pipeline,
            destination: destination,
            pasteHint: pasteHint,
            onUndo: onUndo,
            onDismiss: { [weak self] in self?.dismiss() }
        )
        panel.contentView = view
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        panel.setContentSize(size)
        positionTopRight()
        panel.orderFrontRegardless()

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel.orderOut(nil)
    }

    private func positionTopRight() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - panel.frame.width - 16,
            y: visible.maxY - panel.frame.height - 12
        ))
    }
}
