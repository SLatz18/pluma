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

                Toggle("Suggest as I type", isOn: $coordinator.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!coordinator.isPermissionGranted)
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

            Text("Uses your selected writing model, on-device only. macOS never shares password fields. Suggestions pause while Rewrite's window is frontmost.")
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
