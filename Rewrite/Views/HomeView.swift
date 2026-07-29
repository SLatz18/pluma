import SwiftUI

/// Home: pick a recipe, try it on your own text, then take it system-wide
/// with the shortcut strip. Doing lives here; configuring lives on the
/// feature pages.
struct HomeView: View {
    @EnvironmentObject private var model: RewriteViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.sectionGap) {
                header

                VStack(alignment: .leading, spacing: 12) {
                    DSEyebrow(trigger: "Choose what happens")

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

                AnywhereCard()
            }
            .padding(DS.pagePadding)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(DS.pageBackground)
        .task {
            await model.refreshStatus()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Rewrite anything.")
                    .font(DS.pageTitle)

                Text("Select text. Pick a recipe. Keep your meaning.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 24)

            ProviderMenu()
                .environmentObject(model)
        }
    }
}
