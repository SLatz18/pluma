import SwiftUI

/// Developer-only editor for every recipe prompt. Changes persist immediately
/// and the next rewrite / suggestion / cleanup / summary uses them.
struct PromptEditorCard: View {
    @StateObject private var model = PromptEditorModel()

    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.large) {
                HStack(alignment: .top, spacing: 12) {
                    DSIconTile(systemImage: "text.quote", tint: DS.FeatureColor.rewrite.color)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Recipe prompts")
                            .font(DS.cardTitle)
                        Text("Shown as the model sees them. Edits apply on the next run. Reset restores the shipped text.")
                            .font(DS.cardBody)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if model.hasCustom {
                        Button("Reset All") {
                            model.resetAll()
                        }
                        .controlSize(.small)
                    }
                }

                ForEach(model.groups, id: \.name) { group in
                    DisclosureGroup(group.name) {
                        VStack(alignment: .leading, spacing: DS.Spacing.medium) {
                            ForEach(group.items) { item in
                                promptEditor(item)
                            }
                        }
                        .padding(.top, DS.Spacing.small)
                    }
                    .font(DS.cardBody.weight(.medium))
                }
            }
        }
    }

    private func promptEditor(_ item: RecipePrompt) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.small) {
            HStack {
                Text(item.title)
                    .font(DS.cardBody.weight(.medium))
                if model.isCustom(item) {
                    DSBadge(text: "Custom", tone: .attention)
                }
                Spacer()
                Button("Reset") {
                    model.reset(item)
                }
                .controlSize(.small)
                .disabled(!model.isCustom(item))
            }

            TextEditor(text: model.binding(for: item))
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 88)
                .padding(DS.Spacing.small)
                .dsInsetSurface()
        }
    }
}

@MainActor
final class PromptEditorModel: ObservableObject {
    struct Group {
        let name: String
        let items: [RecipePrompt]
    }

    private static let groupOrder = ["System", "Rewrite", "Autocomplete", "Dictation", "Reader"]

    @Published var drafts: [String: String]

    let groups: [Group]

    var hasCustom: Bool {
        PromptOverrides.catalog.contains { isCustom($0) }
    }

    init() {
        let catalog = PromptOverrides.catalog
        let grouped = Dictionary(grouping: catalog, by: \.group)
        groups = Self.groupOrder.compactMap { name in
            grouped[name].map { Group(name: name, items: $0) }
        }
        drafts = Dictionary(uniqueKeysWithValues: catalog.map { item in
            (item.id, PromptOverrides.text(for: item.id, default: item.defaultText))
        })
    }

    func binding(for item: RecipePrompt) -> Binding<String> {
        Binding(
            get: { self.drafts[item.id] ?? item.defaultText },
            set: { newValue in
                self.objectWillChange.send()
                self.drafts[item.id] = newValue
                PromptOverrides.set(newValue, for: item.id, default: item.defaultText)
            }
        )
    }

    func isCustom(_ item: RecipePrompt) -> Bool {
        let current = (drafts[item.id] ?? item.defaultText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !current.isEmpty && current != item.defaultText
    }

    func reset(_ item: RecipePrompt) {
        PromptOverrides.reset(item.id)
        drafts[item.id] = item.defaultText
    }

    func resetAll() {
        PromptOverrides.resetAll()
        for item in PromptOverrides.catalog {
            drafts[item.id] = item.defaultText
        }
    }
}
