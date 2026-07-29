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

                DictationSettingsCard()

                ShortcutSettingsCard()
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

}
