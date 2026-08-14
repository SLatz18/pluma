import SwiftUI

/// Home: set the system-wide shortcut, pick a recipe pipeline, then try it
/// here before using it in another app.
struct HomeView: View {
    @EnvironmentObject private var model: RewriteViewModel
    @EnvironmentObject private var selectionRewrite: SelectionRewriteController

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        DSFeaturePage(
            .rewrite,
            subtitle: "Select text, run a recipe pipeline, and keep your meaning."
        ) {
            AnywhereCard()

            DSSection(
                "Recipe",
                detail: "Choose recipes in the order they should run."
            ) {
                LazyVGrid(columns: columns, spacing: DS.Spacing.medium) {
                    ForEach(RewriteIntent.allCases) { intent in
                        RecipeActionCard(
                            intent: intent,
                            stepNumber: model.chain.firstIndex(of: intent).map { $0 + 1 }
                        ) {
                            model.toggleInChain(intent)
                        }
                    }
                }
            }

            pipelineStrip

            DSSection("Result", detail: "Try the same pipeline before using it in another app.") {
                PlaygroundView()
                    .environmentObject(model)
            }

            ClipboardFallbackSection()

            DSSharedSettingLink(
                title: "Writing model",
                value: "\(model.provider.title) · \(model.status.title)",
                systemImage: "brain",
                destination: .writing
            )
            .dsCard()
        }
        .task {
            await model.refreshStatus()
        }
    }

    // Trigger on the left, ordered steps after — exactly what the hotkey and
    // the playground will run.
    private var pipelineStrip: some View {
        DSPipelineStrip(isEmpty: model.chain.isEmpty) {
            DSEmptyState(
                title: "No recipe steps",
                detail: "Choose a recipe above. The same pipeline runs here and on selected text with \(selectionRewrite.shortcut.display).",
                systemImage: "sparkles.rectangle.stack"
            )
        } content: {
            triggerPill

            ForEach(Array(model.chain.enumerated()), id: \.element) { index, intent in
                DSPipelineConnector()

                DSPipelineStep(
                    title: intent.title,
                    number: index + 1,
                    tint: intent.feature.color,
                    moveLeft: index > 0
                        ? { model.moveInChain(intent, offset: -1) }
                        : nil,
                    moveRight: index < model.chain.count - 1
                        ? { model.moveInChain(intent, offset: 1) }
                        : nil
                ) {
                    model.removeFromChain(intent)
                }
            }
        }
    }

    private var triggerPill: some View {
        DSBadge(
            text: selectionRewrite.shortcut.display,
            tone: .neutral,
            systemImage: "keyboard"
        )
        .accessibilityLabel("Trigger: press \(selectionRewrite.shortcut.display)")
    }

}

// #47: the clipboard fallback is the path that works in Google Docs and
// Electron apps, so its state and its permission have to be visible rather
// than something the writer discovers by pressing a key and seeing nothing.
// It lives here — not in Settings — because it is a second trigger for the
// same rewrite pipeline configured above.
private struct ClipboardFallbackSection: View {
    @EnvironmentObject private var clipboardRewrite: ClipboardRewriteController

    @State private var isRecording = false

    var body: some View {
        DSSection(
            "Clipboard fallback",
            detail: "A second trigger for the same pipeline, for apps where selecting text does not work."
        ) {
            VStack(spacing: 0) {
                DSToggleRow(
                    title: "Rewrite what I copy",
                    detail: "For apps where selecting text does not work, like Google Docs "
                        + "and Discord. Copy, press \(clipboardRewrite.shortcut.display), then paste.",
                    isOn: Binding(
                        get: { clipboardRewrite.isEnabled },
                        set: { clipboardRewrite.setEnabled($0) }
                    )
                )

                if clipboardRewrite.isEnabled {
                    DSRowDivider()

                    HStack(spacing: 14) {
                        Text(
                            isRecording
                                ? "Press the new shortcut. Caps Lock chords work too. Esc cancels."
                                : "Press this after copying. Rewrites the clipboard in place."
                        )
                        .font(DS.meta)
                        .foregroundStyle(.secondary)

                        Spacer()

                        ShortcutRecorderView(
                            shortcut: clipboardRewrite.shortcut,
                            isRecording: $isRecording,
                            onDismissConflict: clipboardRewrite.clearShortcutConflict
                        ) { shortcut in
                            clipboardRewrite.recordShortcut(shortcut)
                        }
                    }

                    DSRowDivider()

                    DSSettingRow(
                        "Paste from Other Apps",
                        detail: pasteboardPermissionDetail
                    ) {
                        HStack(spacing: DS.Spacing.small) {
                            DSBadge(
                                text: pasteboardPermissionLabel,
                                tone: pasteboardPermissionTone,
                                systemImage: pasteboardPermissionSymbol
                            )
                            Button("Manage…") {
                                PasteboardAccess.openPrivacySettings()
                            }
                        }
                    }

                    if let conflict = clipboardRewrite.shortcutConflict {
                        DSRowDivider()
                        DSNoticeRow(
                            systemImage: "exclamationmark.triangle",
                            tint: .red,
                            text: conflict
                        )
                    }
                }
            }
            .dsCard()
        }
    }

    private var pasteboardPermissionDetail: String {
        switch PasteboardAccess.accessBehavior {
        case .alwaysDeny:
            "macOS is blocking clipboard reads, so this shortcut cannot work. "
                + "Allow pluma under Privacy & Security."
        case .alwaysAllow:
            "pluma can read the clipboard without prompting. Reader uses this as a fallback in Google Docs."
        default:
            "macOS may ask once the first time pluma reads your clipboard."
        }
    }

    private var pasteboardPermissionLabel: String {
        switch PasteboardAccess.accessBehavior {
        case .alwaysDeny: "Denied"
        case .alwaysAllow: "Allowed"
        default: "Asks once"
        }
    }

    private var pasteboardPermissionTone: DS.Tone {
        switch PasteboardAccess.accessBehavior {
        case .alwaysDeny: .attention
        case .alwaysAllow: .success
        default: .neutral
        }
    }

    private var pasteboardPermissionSymbol: String {
        switch PasteboardAccess.accessBehavior {
        case .alwaysDeny: "hand.raised"
        case .alwaysAllow: "checkmark.shield"
        default: "questionmark.circle"
        }
    }
}
