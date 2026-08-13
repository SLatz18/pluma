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
                        title: "Correct misspellings",
                        detail: "Offer a fix for misspelled words before suggesting what comes next. Tab replaces the word.",
                        isOn: $coordinator.spellCorrectionEnabled,
                        disabled: !coordinator.isPermissionGranted
                    )

                    if coordinator.spellCorrectionEnabled {
                        DSRowDivider()
                        DSToggleRow(
                            title: "Remember corrections",
                            detail: "Store accepted fixes locally so repeats are instant. Clear anytime in Settings → Privacy.",
                            isOn: $coordinator.spellMemoryEnabled,
                            disabled: !coordinator.isPermissionGranted
                        )
                    }

                    DSRowDivider()
                    DSToggleRow(
                        title: "Draw suggestions in the line",
                        detail: "Grey text at the caret instead of a chip below it. Works best in native apps; browsers and Electron apps may misplace it.",
                        isOn: $coordinator.inlineSuggestions,
                        disabled: !coordinator.isPermissionGranted
                    )
                }
                .animation(DS.Motion.spring, value: coordinator.spellCorrectionEnabled)
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
        DSFeatureHero(
            systemImage: "character.cursor.ibeam",
            tint: DS.Feature.autocomplete.color,
            title: "Suggestions at the caret",
            detail: "Tab takes the next word, Shift-Tab takes it all, Escape dismisses. Suggestions pause while pluma's window is frontmost.",
            isOn: $coordinator.isEnabled,
            toggleLabel: "Suggest as I type",
            toggleDisabled: !coordinator.isPermissionGranted,
            statusColor: statusColor,
            statusText: statusText,
            notice: coordinator.isPermissionGranted ? nil : DSNoticeRow(
                systemImage: "hand.raised",
                tint: .orange,
                text: "Autocomplete needs Accessibility access to read the field you're typing in.",
                actionTitle: "Grant Accessibility Access…"
            ) {
                coordinator.requestPermission()
            }
        )
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
