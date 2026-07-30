import SwiftUI

struct OverviewView: View {
    @Binding var selection: MainPage?

    @EnvironmentObject private var model: RewriteViewModel
    @EnvironmentObject private var autocomplete: AutocompleteCoordinator
    @EnvironmentObject private var dictation: DictationController

    var body: some View {
        DSPage(
            title: "Overview",
            subtitle: "Your writing automations, permissions, and readiness at a glance.",
            eyebrow: "pluma"
        ) {
            DSSection(
                "Automation health",
                detail: "Open a feature to use or configure it. Shared writing and privacy choices live in Settings."
            ) {
                ForEach(FeatureDefinition.all) { feature in
                    featureCard(feature)
                }
            }

            DSSection("Shared configuration") {
                VStack(spacing: 0) {
                    DSSharedSettingLink(
                        title: "Writing model and personalization",
                        value: model.provider.title,
                        systemImage: "brain",
                        destination: .writing
                    )
                    Divider().padding(.vertical, DS.Spacing.medium)
                    DSSharedSettingLink(
                        title: "Privacy and stored data",
                        value: privacySummary,
                        systemImage: "hand.raised",
                        destination: .privacy
                    )
                }
                .dsCard()
            }
        }
        .accessibilityIdentifier("overview-page")
        .task {
            await model.refreshStatus()
        }
    }

    private func featureCard(_ feature: FeatureDefinition) -> some View {
        Button {
            selection = MainPage(feature.id)
        } label: {
            HStack(alignment: .top, spacing: DS.Spacing.large) {
                DSIconTile(systemImage: feature.symbolName, tint: feature.tint.color)

                VStack(alignment: .leading, spacing: DS.Spacing.small) {
                    HStack {
                        Text(feature.name)
                            .font(DS.cardTitle)
                        Spacer()
                        DSBadge(
                            text: enabled(feature) ? "Enabled" : "Off",
                            tone: enabled(feature) ? .success : .neutral
                        )
                    }

                    Text(feature.trigger)
                        .font(DS.cardBody)
                        .foregroundStyle(.secondary)

                    DSStatusIndicator(tone: tone(feature), text: status(feature))
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, DS.Spacing.medium)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsCard()
        .accessibilityIdentifier("overview-\(feature.id.rawValue)")
    }

    private func enabled(_ feature: FeatureDefinition) -> Bool {
        switch feature.id {
        case .rewrite: !model.chain.isEmpty
        case .autocomplete: autocomplete.isEnabled
        case .dictation: dictation.isEnabled
        }
    }

    private func tone(_ feature: FeatureDefinition) -> DS.Tone {
        return switch feature.id {
        case .rewrite:
            model.chain.isEmpty || !model.status.isReady
                ? DS.Tone.attention
                : DS.Tone.success
        case .autocomplete:
            switch autocomplete.activity {
            case .needsPermission: .attention
            case .watching, .suggesting: .success
            case .off: .neutral
            }
        case .dictation:
            switch dictation.activity {
            case .needsPermission, .preparing, .unavailable: .attention
            case .listening: .recording
            case .idle, .tidying: .success
            case .off: .neutral
            }
        }
    }

    private func status(_ feature: FeatureDefinition) -> String {
        switch feature.id {
        case .rewrite:
            if model.chain.isEmpty { return feature.disabledStatus }
            return model.status.isReady
                ? "\(model.chain.count) recipe step\(model.chain.count == 1 ? "" : "s") ready"
                : model.status.title
        case .autocomplete:
            return switch autocomplete.activity {
            case .off: feature.disabledStatus
            case .needsPermission: "Needs Accessibility access"
            case .watching: feature.enabledStatus
            case .suggesting: "Suggestion showing"
            }
        case .dictation:
            return switch dictation.activity {
            case .off: feature.disabledStatus
            case .needsPermission: "Needs microphone access"
            case .preparing: "Preparing speech recognition"
            case .idle: feature.enabledStatus
            case .listening: "Listening"
            case .tidying: "Cleaning up transcript"
            case .unavailable(let reason): reason
            }
        }
    }

    private var privacySummary: String {
        if model.provider == .appleIntelligence {
            return "On-device writing model"
        }
        return "Loopback writing model"
    }
}
