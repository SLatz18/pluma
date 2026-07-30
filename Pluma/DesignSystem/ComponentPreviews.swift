#if DEBUG
import SwiftUI

#Preview("Automation flows") {
    ScrollView {
        VStack(spacing: PlumaTheme.Spacing.xLarge) {
            ForEach(FeatureDefinition.all) { feature in
                DSSection(feature.name) {
                    DSAutomationFlow(definition: feature)
                        .dsCard()
                }
            }
        }
        .padding(PlumaTheme.pagePadding)
    }
    .frame(width: 900, height: 760)
}

#Preview("Component states") {
    VStack(alignment: .leading, spacing: PlumaTheme.Spacing.large) {
        HStack {
            DSBadge(text: "Normal")
            DSBadge(text: "Selected", tone: .success, systemImage: "checkmark")
            DSBadge(text: "Permission", tone: .attention, systemImage: "hand.raised")
            DSBadge(text: "Error", tone: .failure, systemImage: "xmark")
        }

        DSToggleRow(
            title: "Enabled setting",
            detail: "A shared row with supporting text.",
            isOn: .constant(true)
        )

        DSToggleRow(
            title: "Disabled setting",
            detail: "The same shared row in a disabled state.",
            isOn: .constant(false),
            disabled: true
        )

        DSNoticeRow(
            systemImage: "hand.raised",
            tint: .orange,
            text: "Permission is required.",
            actionTitle: "Grant…",
            action: {}
        )

        DSEmptyState(
            title: "No results",
            detail: "Try a different filter.",
            systemImage: "tray"
        )
    }
    .padding(PlumaTheme.pagePadding)
    .frame(width: 640)
}
#endif
