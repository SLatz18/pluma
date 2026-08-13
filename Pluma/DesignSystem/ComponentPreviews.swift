#if DEBUG
import AppKit
import SwiftUI

// Wraps the live overlay's own AppKit views so the previews show exactly what
// appears at the caret — same renderer, same fonts, same tints. Preview-only;
// the overlay itself never goes through SwiftUI (see OverlayPillRenderer's
// header for why).
private struct OverlayPillPreview: NSViewRepresentable {
    enum Kind {
        case suggestion(String)
        case status(systemImage: String, message: String, tone: OverlayTone, pulses: Bool)
        case dictation(String)
    }

    let kind: Kind

    func makeNSView(context: Context) -> OverlayPillRenderer {
        let pill = OverlayPillRenderer(frame: .zero)
        apply(to: pill)
        return pill
    }

    func updateNSView(_ pill: OverlayPillRenderer, context: Context) {
        apply(to: pill)
    }

    private func apply(to pill: OverlayPillRenderer) {
        switch kind {
        case let .suggestion(text):
            pill.showSuggestion(text)
        case let .status(systemImage, message, tone, pulses):
            pill.showStatus(systemImage: systemImage, message: message, tone: tone, pulses: pulses)
        case let .dictation(transcript):
            pill.showDictation(transcript: transcript)
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: OverlayPillRenderer, context: Context
    ) -> CGSize {
        nsView.fittingSize
    }
}

private struct GhostTextPreview: NSViewRepresentable {
    let text: String
    let style: GhostStyle
    var fontSize: CGFloat = 13

    func makeNSView(context: Context) -> GhostTextView {
        let ghost = GhostTextView(frame: .zero)
        apply(to: ghost)
        return ghost
    }

    func updateNSView(_ ghost: GhostTextView, context: Context) {
        apply(to: ghost)
    }

    private func apply(to ghost: GhostTextView) {
        ghost.show(
            text: text,
            style: style,
            font: .systemFont(ofSize: fontSize),
            maxWidth: 420
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: GhostTextView, context: Context
    ) -> CGSize {
        nsView.fittingSize
    }
}

#Preview("Caret overlay") {
    VStack(alignment: .leading, spacing: PlumaTheme.Spacing.large) {
        DSSection("Suggestion pill") {
            OverlayPillPreview(kind: .suggestion("continue the sentence like this"))
                .fixedSize()
        }

        DSSection("Status pill — every tone") {
            VStack(alignment: .leading, spacing: PlumaTheme.Spacing.small) {
                OverlayPillPreview(kind: .status(
                    systemImage: "ellipsis", message: "Working…",
                    tone: .neutral, pulses: false
                ))
                .fixedSize()
                OverlayPillPreview(kind: .status(
                    systemImage: "wand.and.stars", message: "Rewriting selection",
                    tone: .accent, pulses: false
                ))
                .fixedSize()
                OverlayPillPreview(kind: .status(
                    systemImage: "mic.fill", message: "Transcribing…",
                    tone: .recording, pulses: true
                ))
                .fixedSize()
                OverlayPillPreview(kind: .status(
                    systemImage: "hand.raised", message: "Accessibility access needed",
                    tone: .warning, pulses: false
                ))
                .fixedSize()
                OverlayPillPreview(kind: .status(
                    systemImage: "xmark.octagon", message: "Model unavailable",
                    tone: .failure, pulses: false
                ))
                .fixedSize()
            }
        }

        DSSection("Dictation pill") {
            VStack(alignment: .leading, spacing: PlumaTheme.Spacing.small) {
                OverlayPillPreview(kind: .dictation(""))
                    .fixedSize()
                OverlayPillPreview(kind: .dictation("the words arrive as they are spoken"))
                    .fixedSize()
            }
        }

        DSSection("Ghost text") {
            VStack(alignment: .leading, spacing: PlumaTheme.Spacing.small) {
                (Text("The report is ").foregroundColor(.primary)
                    + Text("(ghost continues below)").font(.caption).foregroundColor(.secondary))
                GhostTextPreview(text: "nearly ready for review", style: .suggestion)
                    .fixedSize()
                GhostTextPreview(text: "dictated words landing at the caret", style: .dictation)
                    .fixedSize()
            }
            .dsCard()
        }
    }
    .padding(PlumaTheme.pagePadding)
    .frame(width: 640)
}

#Preview("Automation flows") {
    ScrollView {
        VStack(spacing: PlumaTheme.Spacing.xLarge) {
            ForEach(FeatureDefinition.all) { feature in
                DSSection(feature.name) {
                    DSAutomationFlow(definition: feature)
                        .dsCard()
                }
            }
        }
        .padding(PlumaTheme.pagePadding)
    }
    .frame(width: 900, height: 760)
}

#Preview("Component states") {
    VStack(alignment: .leading, spacing: PlumaTheme.Spacing.large) {
        HStack {
            DSBadge(text: "Normal")
            DSBadge(text: "Selected", tone: .success, systemImage: "checkmark")
            DSBadge(text: "Permission", tone: .attention, systemImage: "hand.raised")
            DSBadge(text: "Error", tone: .failure, systemImage: "xmark")
        }

        DSToggleRow(
            title: "Enabled setting",
            detail: "A shared row with supporting text.",
            isOn: .constant(true)
        )

        DSToggleRow(
            title: "Disabled setting",
            detail: "The same shared row in a disabled state.",
            isOn: .constant(false),
            disabled: true
        )

        DSNoticeRow(
            systemImage: "hand.raised",
            tint: .orange,
            text: "Permission is required.",
            actionTitle: "Grant…",
            action: {}
        )

        DSEmptyState(
            title: "No results",
            detail: "Try a different filter.",
            systemImage: "tray"
        )
    }
    .padding(PlumaTheme.pagePadding)
    .frame(width: 640)
}
#endif
