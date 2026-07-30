import SwiftUI

struct AutocompleteView: View {
    @EnvironmentObject private var coordinator: AutocompleteCoordinator
    @State private var showClearMemoryConfirmation = false

    var body: some View {
        DSPage(
            title: "Autocomplete",
            subtitle: "Ghost-text suggestions as you type, in every app.",
            eyebrow: "As you type → suggest"
        ) {
            heroCard

            VStack(alignment: .leading, spacing: 12) {
                DSEyebrow(trigger: "Personalization")

                VStack(spacing: 0) {
                    DSToggleRow(
                        title: "Screen context",
                        detail: "OCR the frontmost window so completions can match what you're replying to — names, topics, tone. Nothing is stored.",
                        isOn: $coordinator.screenContextEnabled,
                        disabled: !coordinator.isPermissionGranted
                    )

                    if coordinator.screenContextEnabled && !coordinator.isScreenContextPermitted {
                        rowDivider
                        DSNoticeRow(
                            systemImage: "rectangle.dashed.badge.record",
                            tint: .orange,
                            text: "Screen context needs Screen Recording access to read text near your cursor.",
                            actionTitle: "Grant Screen Recording…"
                        ) {
                            coordinator.requestScreenContextPermission()
                        }
                    }

                    rowDivider

                    DSToggleRow(
                        title: "Learn my style",
                        detail: "Accepted phrases become local style memory, steering suggestions toward your vocabulary.",
                        isOn: $coordinator.memoryEnabled,
                        disabled: !coordinator.isPermissionGranted
                    )

                    if coordinator.memoryEnabled {
                        rowDivider
                        DSNoticeRow(
                            systemImage: "brain",
                            tint: .secondary,
                            text: coordinator.memoryEntryCount == 0
                                ? "No phrases yet — accepted suggestions become style memory."
                                : "\(coordinator.memoryEntryCount) phrases remembered, stored locally only.",
                            actionTitle: coordinator.memoryEntryCount > 0 ? "Clear…" : nil
                        ) {
                            showClearMemoryConfirmation = true
                        }
                    }
                }
                .dsCard()
            }

            VStack(alignment: .leading, spacing: 12) {
                DSEyebrow(trigger: "Appearance")

                VStack(spacing: 0) {
                    DSToggleRow(
                        title: "Draw suggestions in the line",
                        detail: "Grey text continuing your sentence at the caret, instead of a chip below it. Needs the app to report its font and caret precisely — native apps do, most browsers and Electron apps don't, and there it will sit off the line.",
                        isOn: $coordinator.inlineSuggestions,
                        disabled: !coordinator.isPermissionGranted
                    )
                }
                .dsCard()
            }

            Text("Uses your selected writing model (Apple Intelligence on-device, or Ollama on loopback). macOS never shares password fields. Manage memory and import a style profile in Settings → Advanced.")
                .font(DS.meta)
                .foregroundStyle(.tertiary)
        }
        .confirmationDialog(
            "Clear all remembered phrases?",
            isPresented: $showClearMemoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                coordinator.clearMemory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes every stored phrase from this Mac and cannot be undone.")
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                DSIconTile(systemImage: "character.cursor.ibeam", tint: DS.Feature.autocomplete.color)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Suggestions at the caret")
                        .font(DS.cardTitle)
                    Text("Tab takes the next word, Shift-Tab takes it all, Escape dismisses. Suggestions pause while pluma's window is frontmost.")
                        .font(DS.cardBody)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Toggle("Suggest as I type", isOn: $coordinator.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!coordinator.isPermissionGranted)
            }

            DSStatusRow(color: statusColor, text: statusText)

            if !coordinator.isPermissionGranted {
                DSNoticeRow(
                    systemImage: "hand.raised",
                    tint: .orange,
                    text: "Autocomplete needs Accessibility access to read the field you're typing in.",
                    actionTitle: "Grant Accessibility Access…"
                ) {
                    coordinator.requestPermission()
                }
            }
        }
        .dsCard()
    }

    private var rowDivider: some View {
        Divider()
            .padding(.vertical, 10)
    }

    private var statusColor: Color {
        switch coordinator.activity {
        case .off: .gray
        case .needsPermission: .orange
        case .watching: .green
        case .suggesting: .green
        }
    }

    private var statusText: String {
        switch coordinator.activity {
        case .off:
            "Autocomplete is off"
        case .needsPermission:
            "Needs Accessibility access to read the field you're typing in"
        case .watching:
            "Watching for a text field"
        case .suggesting:
            "Suggestion showing"
        }
    }
}
