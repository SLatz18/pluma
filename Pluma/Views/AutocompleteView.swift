import SwiftUI

struct AutocompleteView: View {
    @EnvironmentObject private var coordinator: AutocompleteCoordinator

    var body: some View {
        DSFeaturePage(
            .autocomplete,
            subtitle: "Suggestions appear at the caret while you type in any app."
        ) {
            heroCard

            DSSection("Suggestion appearance") {
                VStack(spacing: 0) {
                    DSToggleRow(
                        title: "Draw suggestions in the line",
                        detail: "Grey text continuing your sentence at the caret, instead of a chip below it. Needs the app to report its font and caret precisely — native apps do, most browsers and Electron apps don't, and there it will sit off the line.",
                        isOn: $coordinator.inlineSuggestions,
                        disabled: !coordinator.isPermissionGranted
                    )
                    DSRowDivider()
                    DSToggleRow(
                        title: "Correct misspellings",
                        detail: "When you finish a misspelled word — or pause mid-word — offer a fix on the chip before suggesting what comes next. Tab replaces the word. Uses Apple Intelligence on-device by default; Developer can switch to the Mac spelling dictionary.",
                        isOn: $coordinator.spellCorrectionEnabled,
                        disabled: !coordinator.isPermissionGranted
                    )
                    DSRowDivider()
                    DSToggleRow(
                        title: "Remember corrections",
                        detail: "When you accept a fix, store that misspelling locally so the next time is instant — no dictionary wait, no model call. Clear anytime in Settings → Privacy.",
                        isOn: $coordinator.spellMemoryEnabled,
                        disabled: !coordinator.spellCorrectionEnabled || !coordinator.isPermissionGranted
                    )
                }
                .dsCard()
            }

            DSSharedSettingLink(
                title: "Model, screen context, and style",
                value: sharedSettingsSummary,
                systemImage: "brain",
                destination: .writing
            )
            .dsCard()

            Text("macOS never shares password fields. Accepted style memory and spelling corrections are stored only when enabled, and can be managed in Settings → Privacy.")
                .font(DS.meta)
                .foregroundStyle(.tertiary)
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

    private var sharedSettingsSummary: String {
        var parts: [String] = []
        parts.append(coordinator.screenContextEnabled ? "Screen context on" : "Screen context off")
        parts.append(coordinator.memoryEnabled ? "Style learning on" : "Style learning off")
        return parts.joined(separator: " · ")
    }
}
