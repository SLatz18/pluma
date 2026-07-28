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

                RewritePlaygroundView()
                    .environmentObject(model)

                AutocompleteSettingsCard()

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

    private var shortcutSetup: some View {
        HStack(spacing: 14) {
            HStack(spacing: 3) {
                ForEach(["⌃", "⌥", "⇧", "⌘", "E"], id: \.self) { key in
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
                Text("Hyperkey ready")
                    .font(.headline)
                Text("Assign Hyperkey + E to “Edit with Rewrite” once in Keyboard Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Set Shortcut…") {
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
