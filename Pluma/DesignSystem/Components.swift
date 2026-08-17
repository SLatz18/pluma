import SwiftUI

// One visual language for the whole app. Every surface, icon tile, eyebrow,
// and status row comes from here so a feature page and the playground can
// never drift into different dialects.
//
// The grammar is WHEN → THEN → RESULT: an uppercase eyebrow names the
// trigger ("SELECTED TEXT", "AS YOU TYPE"), an arrow, then the outcome. If a
// new surface can't state its trigger, it doesn't get an eyebrow.
//
// Feature pages stack DSFeaturePage → DSFeatureHero → DSShortcutCard →
// recipe section → other DSSection blocks → DSSharedSettingLink +
// DSPageFootnote. Rewrite has no hero, because recipe selection is the
// enablement, but the recipe section still sits in the same slot: first
// section after the shortcut card.
// MARK: - Card surface

struct DSCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content.dsCard()
    }
}

extension View {
    func dsCard() -> some View {
        padding(DS.cardPadding)
            .background(DS.cardBackground, in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                    .strokeBorder(DS.hairline)
            }
            .shadow(color: .black.opacity(0.05), radius: 1.5, y: 1)
    }

    func dsInsetSurface() -> some View {
        background(
            DS.insetBackground,
            in: RoundedRectangle(cornerRadius: DS.insetRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DS.insetRadius, style: .continuous)
                .strokeBorder(DS.hairline)
        }
    }
}

// MARK: - Icon tile

/// The 42 pt tinted rounded square that anchors every card header.
struct DSIconTile: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = DS.Control.iconTile
    var symbolSize: CGFloat = 19

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: symbolSize, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: DS.tileRadius, style: .continuous))
    }
}

// MARK: - Row divider

/// The padded divider between setting rows inside a card.
struct DSRowDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, DS.Spacing.medium)
    }
}

// MARK: - Eyebrow (trigger → action)

/// Trigger → action rendered as type: TRIGGER  →  outcome, uppercase,
/// tracked out, tertiary. `action` stays unstyled-uppercase so the pair reads
/// as one sentence.
struct DSEyebrow: View {
    let trigger: String
    var action: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            Text(trigger.uppercased())
            if let action {
                Image(systemName: "arrow.right")
                Text(action.uppercased())
            }
        }
        .font(DS.eyebrow)
        .tracking(0.6)
        .foregroundStyle(.tertiary)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Status row

/// The 8 pt dot + caption that reports liveness at the bottom of a card.
struct DSStatusRow: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(DS.meta)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Permission / notice row

/// Icon + explanation + trailing action, used for grants and warnings.
struct DSNoticeRow: View {
    let systemImage: String
    let tint: Color
    let text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(text)
                .font(DS.meta)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
        }
    }
}

// MARK: - Labeled switch row

/// One switch with its own row: bold label, description, toggle at the
/// trailing edge. Replaces the cramped caption-label toggle stacks.
struct DSToggleRow: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool
    var disabled: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.cardBody.weight(.medium))
                if let detail {
                    Text(detail)
                        .font(DS.meta)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(disabled)
        }
        .disabled(disabled)
        .foregroundStyle(disabled ? .tertiary : .primary)
    }
}

// MARK: - Feature hero

/// The lead card on a feature page: icon tile, title, description, trailing
/// enable switch, a status row, and an optional permission notice. Keeps
/// Autocomplete, Dictation, and Reader visually identical. Rewrite has no
/// hero — recipe selection is the enablement.
struct DSFeatureHero: View {
    let systemImage: String
    let tint: Color
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var toggleLabel: String = "Enabled"
    var toggleDisabled: Bool = false
    let statusColor: Color
    let statusText: String
    var notice: DSNoticeRow? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                DSIconTile(systemImage: systemImage, tint: tint)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(DS.cardTitle)
                    Text(detail)
                        .font(DS.cardBody)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Toggle(toggleLabel, isOn: $isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(toggleDisabled)
            }

            DSStatusRow(color: statusColor, text: statusText)

            if let notice {
                notice
            }
        }
        .dsCard()
    }
}

// MARK: - Shortcut card

/// The shared shortcut recorder surface: optional icon and eyebrow, a title,
/// explainer copy, the recorder, and a conflict row. Rewrite's AnywhereCard
/// wraps this; Dictation and Reader use it directly.
struct DSShortcutCard: View {
    var systemImage: String? = nil
    var tint: Color = DS.Feature.shortcut.color
    var eyebrowTrigger: String? = nil
    var eyebrowAction: String? = nil
    var title: String? = nil
    let detail: String
    let shortcut: GlobalShortcut
    @Binding var isRecording: Bool
    var conflict: String? = nil
    var onDismissConflict: () -> Void = {}
    let onRecord: (GlobalShortcut) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                if let systemImage {
                    DSIconTile(systemImage: systemImage, tint: tint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let eyebrowTrigger {
                        DSEyebrow(trigger: eyebrowTrigger, action: eyebrowAction)
                    }
                    if let title {
                        Text(title)
                            .font(DS.cardTitle)
                    }
                    Text(detail)
                        .font(DS.meta)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                ShortcutRecorderView(
                    shortcut: shortcut,
                    isRecording: $isRecording,
                    onDismissConflict: onDismissConflict,
                    onRecord: onRecord
                )
            }

            if let conflict {
                Label(conflict, systemImage: "exclamationmark.triangle.fill")
                    .font(DS.meta)
                    .foregroundStyle(.orange)
            }
        }
        .dsCard()
    }
}

// MARK: - Page scaffold

/// Every sidebar page: optional eyebrow, subtitle, then the page content on
/// the shared page background. The page title lives in the window toolbar
/// (Safari-style chrome), so this scaffold does not repeat it inline.
struct DSPage<Content: View>: View {
    let title: String
    let subtitle: String
    var eyebrow: String? = nil
    var scrollTarget: String? = nil
    var pageIdentifier: String? = nil
    let content: Content

    init(
        title: String,
        subtitle: String,
        eyebrow: String? = nil,
        scrollTarget: String? = nil,
        pageIdentifier: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.eyebrow = eyebrow
        self.scrollTarget = scrollTarget
        self.pageIdentifier = pageIdentifier
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sectionGap) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let eyebrow {
                            DSEyebrow(trigger: eyebrow)
                        }
                        if let pageIdentifier {
                            Text(subtitle)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier(pageIdentifier)
                        } else {
                            Text(subtitle)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }

                    content
                }
                .padding(DS.pagePadding)
                .frame(maxWidth: DS.Control.pageMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .task(id: scrollTarget) {
                guard let scrollTarget else { return }
                await Task.yield()
                withAnimation(DS.Motion.spring) {
                    proxy.scrollTo(scrollTarget, anchor: .center)
                }
            }
        }
        .background(DS.pageBackground)
        .accessibilityLabel(title)
    }
}

struct DSFeaturePage<Content: View>: View {
    let definition: FeatureDefinition
    let subtitle: String
    var scrollTarget: String? = nil
    let content: Content

    init(
        _ definition: FeatureDefinition,
        subtitle: String,
        scrollTarget: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.definition = definition
        self.subtitle = subtitle
        self.scrollTarget = scrollTarget
        self.content = content()
    }

    var body: some View {
        DSPage(
            title: definition.name,
            subtitle: subtitle,
            eyebrow: "How it works",
            scrollTarget: scrollTarget,
            pageIdentifier: "\(definition.id.rawValue)-page"
        ) {
            DSAutomationFlow(definition: definition)
                .dsCard()
            content
        }
    }
}

/// Tertiary privacy or processing note at the bottom of a feature page.
struct DSPageFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DS.meta)
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Automation language

struct DSAutomationFlow: View {
    let definition: FeatureDefinition

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.small) {
            step(.when, definition.trigger)
            connector
            step(.then, definition.action)
            connector
            step(.result, definition.result)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(definition.name) automation flow")
    }

    private func step(_ kind: AutomationStep, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.small) {
            Text(kind.rawValue)
                .font(DS.eyebrow)
                .tracking(0.7)
                .foregroundStyle(definition.tint.color)
            Text(text)
                .font(DS.cardBody.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .padding(DS.Spacing.medium)
        .background(
            definition.tint.color.opacity(0.05),
            in: RoundedRectangle(cornerRadius: DS.insetRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DS.insetRadius, style: .continuous)
                .strokeBorder(definition.tint.color.opacity(0.16))
        }
    }

    private var connector: some View {
        Image(systemName: "arrow.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(definition.tint.color.opacity(0.55))
            .frame(width: 12, height: 62)
    }
}

struct DSSection<Content: View>: View {
    let title: String
    var detail: String?
    var identifier: String?
    let content: Content

    init(
        _ title: String,
        detail: String? = nil,
        identifier: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.identifier = identifier
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.medium) {
            VStack(alignment: .leading, spacing: DS.Spacing.xSmall) {
                sectionTitle
                if let detail {
                    Text(detail)
                        .font(DS.meta)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
    }

    @ViewBuilder
    private var sectionTitle: some View {
        if let identifier {
            Text(title)
                .font(DS.cardTitle)
                .accessibilityIdentifier(identifier)
        } else {
            Text(title)
                .font(DS.cardTitle)
        }
    }
}

struct DSSettingRow<Trailing: View>: View {
    let title: String
    let detail: String?
    let trailing: Trailing

    init(
        _ title: String,
        detail: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.medium) {
            VStack(alignment: .leading, spacing: DS.Spacing.xSmall) {
                Text(title)
                    .font(DS.cardBody.weight(.medium))
                if let detail {
                    Text(detail)
                        .font(DS.meta)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: DS.Spacing.medium)
            trailing
        }
    }
}

struct DSSharedSettingLink: View {
    let title: String
    let value: String
    let systemImage: String
    var destination: SettingsDestination = .writing
    var focus: NavigationFocus? = nil
    var returnToCurrentPage = false
    var returnFocus: NavigationFocus? = nil

    @ObservedObject private var navigation = MainNavigation.shared

    var body: some View {
        // Settings are sidebar pages in the same window, so a shared-setting
        // link is plain navigation — the page it names is the page it shows.
        Button {
            navigation.navigate(
                to: destination.mainPage,
                focus: focus,
                returningTo: returnToCurrentPage ? navigation.page : nil,
                returnFocus: returnFocus
            )
        } label: {
            HStack(spacing: DS.Spacing.medium) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: DS.Spacing.xSmall) {
                    Text(title)
                        .font(DS.cardBody.weight(.medium))
                    Text(value)
                        .font(DS.meta)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(destination.title)
                    .font(DS.meta)
                    .foregroundStyle(.tertiary)
                Image(systemName: "arrow.up.forward.app")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shared-setting-\(destination.rawValue)")
    }
}

struct DSContextualBackLink: View {
    let page: MainPage

    @ObservedObject private var navigation = MainNavigation.shared

    @ViewBuilder
    var body: some View {
        if let returnPage = navigation.returnPage(from: page) {
            Button {
                navigation.goBack(from: page)
            } label: {
                Label("Back to \(returnPage.title)", systemImage: "arrow.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("contextual-back-\(returnPage.rawValue)")
        }
    }
}

struct DSStatusIndicator: View {
    let tone: DS.Tone
    let text: String

    var body: some View {
        HStack(spacing: DS.Spacing.small) {
            Circle()
                .fill(tone.color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(DS.meta)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(tone.rawValue)
    }
}

struct DSBadge: View {
    let text: String
    var tone: DS.Tone = .neutral
    var systemImage: String?

    var body: some View {
        HStack(spacing: DS.Spacing.xSmall) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(DS.meta.weight(.semibold))
        .foregroundStyle(tone.color)
        .padding(.horizontal, DS.Spacing.small)
        .frame(minHeight: DS.Control.shortcutHeight)
        .background(
            tone.color.opacity(0.1),
            in: RoundedRectangle(cornerRadius: DS.Radius.badge, style: .continuous)
        )
    }
}

struct DSInset<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(DS.Spacing.medium)
            .background(
                DS.insetBackground,
                in: RoundedRectangle(cornerRadius: DS.insetRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DS.insetRadius, style: .continuous)
                    .strokeBorder(DS.hairline)
            }
    }
}

struct DSSelectableCard<Content: View>: View {
    let isSelected: Bool
    let tint: Color
    let selectedLineWidth: CGFloat
    let action: () -> Void
    let content: Content

    init(
        isSelected: Bool,
        tint: Color,
        selectedLineWidth: CGFloat = 1,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.tint = tint
        self.selectedLineWidth = selectedLineWidth
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            content
                .padding(DS.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isSelected ? tint.opacity(0.08) : DS.cardBackground,
                    in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                        .strokeBorder(
                            isSelected ? tint.opacity(0.55) : DS.hairline,
                            lineWidth: isSelected ? selectedLineWidth : 1
                        )
                }
        }
        .buttonStyle(.plain)
    }
}

struct DSPipelineStep: View {
    let title: String
    let number: Int
    let tint: Color
    var moveLeft: (() -> Void)? = nil
    var moveRight: (() -> Void)? = nil
    var remove: (() -> Void)? = nil

    private var isReorderable: Bool { moveLeft != nil || moveRight != nil }

    var body: some View {
        HStack(spacing: DS.Spacing.small) {
            Image(systemName: "\(number).circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(DS.meta.weight(.medium))
            if isReorderable {
                HStack(spacing: 2) {
                    Button(action: { moveLeft?() }) {
                        Image(systemName: "chevron.left")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(moveLeft == nil ? .quaternary : .tertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(moveLeft == nil)
                    .accessibilityLabel("Move \(title) earlier in pipeline")

                    Button(action: { moveRight?() }) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(moveRight == nil ? .quaternary : .tertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(moveRight == nil)
                    .accessibilityLabel("Move \(title) later in pipeline")
                }
            }
            if let remove {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(title) from pipeline")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            if let moveLeft {
                Button("Move \(title) earlier", action: moveLeft)
            }
            if let moveRight {
                Button("Move \(title) later", action: moveRight)
            }
        }
        .padding(.horizontal, DS.Spacing.medium)
        .padding(.vertical, DS.Spacing.small)
        .background(
            DS.cardBackground,
            in: RoundedRectangle(cornerRadius: DS.insetRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DS.insetRadius, style: .continuous)
                .strokeBorder(tint.opacity(0.35))
        }
    }
}

/// Horizontal path/pipeline strip. Rewrite keeps the default
/// "Your pipeline → runs left to right" eyebrow; Autocomplete, Dictation,
/// and Reader omit it (directives, cleanup steps, and listening mode are
/// not sequential rewrite recipes). Pass `isEmpty` plus `empty:` for the
/// no-steps placeholder.
struct DSPipelineStrip<Content: View, Empty: View>: View {
    var eyebrowTrigger: String? = "Your pipeline"
    var eyebrowAction: String? = "runs left to right"
    var isEmpty: Bool = false
    let empty: Empty
    let content: Content

    init(
        eyebrowTrigger: String? = "Your pipeline",
        eyebrowAction: String? = "runs left to right",
        isEmpty: Bool = false,
        @ViewBuilder empty: () -> Empty,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrowTrigger = eyebrowTrigger
        self.eyebrowAction = eyebrowAction
        self.isEmpty = isEmpty
        self.empty = empty()
        self.content = content()
    }

    init(
        eyebrowTrigger: String? = "Your pipeline",
        eyebrowAction: String? = "runs left to right",
        @ViewBuilder content: () -> Content
    ) where Empty == EmptyView {
        self.eyebrowTrigger = eyebrowTrigger
        self.eyebrowAction = eyebrowAction
        self.isEmpty = false
        self.empty = EmptyView()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let eyebrowTrigger {
                DSEyebrow(trigger: eyebrowTrigger, action: eyebrowAction)
            }

            if isEmpty {
                empty
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        content
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

struct DSPipelineConnector: View {
    var body: some View {
        Image(systemName: "arrow.right")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.tertiary)
    }
}

struct DSEmptyState: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(detail))
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(
                DS.insetBackground,
                in: RoundedRectangle(cornerRadius: DS.insetRadius, style: .continuous)
            )
    }
}
