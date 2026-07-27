import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: RewriteViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose what happens")
                        .font(.headline)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(RewriteIntent.allCases) { intent in
                            RewriteActionCard(
                                intent: intent,
                                isSelected: model.selectedIntent == intent
                            ) {
                                model.selectIntent(intent)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Add a style")
                            .font(.headline)
                        Spacer()
                        Text("Optional — layers onto the action")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 8) {
                        ForEach(model.availableProfiles) { profile in
                            profileChip(profile)
                        }
                    }
                }

                RewritePlaygroundView()
                    .environmentObject(model)

                shortcutSetup
            }
            .padding(32)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 720, minHeight: 640)
        .task {
            await model.refreshStatus()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Rewrite anything.")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                Text("Select text. Pick an action. Keep your meaning.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 24)

            ProviderMenu()
                .environmentObject(model)
        }
    }

    private func profileChip(_ profile: StyleProfile) -> some View {
        let isSelected = model.selectedProfileID == profile.id
        return Button {
            model.selectProfile(profile.id)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(profile.name)
                        .font(.callout.weight(.semibold))
                    if profile.isManaged {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(profile.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.1)
                    : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.07),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .help(profile.isManaged ? "Managed by your organization" : profile.summary)
    }

    private var shortcutSetup: some View {
        HStack(spacing: 14) {
            HStack(spacing: 3) {
                ForEach(["\u{2303}", "\u{2325}", "\u{21E7}", "\u{2318}", "E"], id: \.self) { key in
                    Text(key)
                        .font(.caption.weight(.semibold))
                        .frame(minWidth: key == "E" ? 22 : 18, minHeight: 22)
                        .background(
                            Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.primary.opacity(0.12))
                        }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Copy \u{2192} hotkey \u{2192} paste")
                    .font(.headline)
                Text("Copy text anywhere (yes, Google Docs), press the hotkey, paste the fix.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Set Shortcut\u{2026}") {
                model.openKeyboardSettings()
            }
        }
        .padding(16)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}
