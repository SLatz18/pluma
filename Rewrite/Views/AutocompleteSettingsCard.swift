import SwiftUI

struct AutocompleteSettingsCard: View {
    @EnvironmentObject private var coordinator: AutocompleteCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "character.cursor.ibeam")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Autocomplete everywhere")
                        .font(.headline)
                    Text("Ghost-text suggestions as you type in any app. Tab takes the next word, Shift-Tab takes it all, Escape dismisses.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    Toggle("Suggest as I type", isOn: $coordinator.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!coordinator.isPermissionGranted)

                    HStack(spacing: 6) {
                        Text("Screen context")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle("Screen context", isOn: $coordinator.screenContextEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(!coordinator.isPermissionGranted)
                    }

                    HStack(spacing: 6) {
                        Text("Learn my style")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle("Learn my style", isOn: $coordinator.memoryEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(!coordinator.isPermissionGranted)
                    }
                }
            }

            if coordinator.memoryEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "brain")
                        .foregroundStyle(.secondary)
                    Text(
                        coordinator.memoryEntryCount == 0
                            ? "No phrases yet — accepted suggestions become style memory."
                            : "\(coordinator.memoryEntryCount) phrases remembered, stored locally only."
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if coordinator.memoryEntryCount > 0 {
                        Button("Clear…") {
                            coordinator.clearMemory()
                        }
                        .controlSize(.small)
                    }
                }
            }

            if coordinator.screenContextEnabled && !coordinator.isScreenContextPermitted {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.dashed.badge.record")
                        .foregroundStyle(.orange)
                    Text("Screen context needs Screen Recording access to read text near your cursor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Grant Screen Recording…") {
                        coordinator.requestScreenContextPermission()
                    }
                    .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if !coordinator.isPermissionGranted {
                    Button("Grant Accessibility Access…") {
                        coordinator.requestPermission()
                    }
                    .controlSize(.small)
                }
            }

            Text("Uses your selected writing model, on-device only. Screen context OCRs the frontmost window in real time and stores nothing. macOS never shares password fields. Suggestions pause while Rewrite's window is frontmost.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
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
}
