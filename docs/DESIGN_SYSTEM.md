# Pluma design system

Pluma's user-facing language is a native macOS automation:

**WHEN** a trigger happens → **THEN** pluma acts → **RESULT** describes what
the writer can accept, dismiss, insert, or test.

## Source of truth

All semantic tokens and reusable components live in `Pluma/DesignSystem`.

- `PlumaTheme` owns color, typography, spacing, radius, control, motion, and
  AppKit overlay values.
- `FeatureDefinition` owns feature names, symbols, tints, flow copy, and status
  vocabulary.
- `Components.swift` owns cards, pages, automation steps, setting rows,
  notices, badges, insets, empty states, and shared-setting links.
- `OverlayPresentation` is the semantic input to the single pure-AppKit
  floating-pill renderer.

Use semantic macOS colors and SF Symbols. Do not introduce a raw feature color,
corner radius, type size, locally constructed card, badge, or pill in a
user-facing view.

## Page composition

Feature pages use `DSFeaturePage`, which supplies the shared header and
WHEN → THEN → RESULT flow. Put feature-specific controls below it. Shared
writing, context, style, and privacy settings appear once in Settings and are
referenced from features with `DSSharedSettingLink`.

Use:

- `DSCard` or `.dsCard()` for a raised surface.
- `DSInset` for editors and readouts inside a card.
- `DSSettingRow` or `DSToggleRow` for preferences.
- `DSStatusIndicator` for neutral, ready, attention, recording, or failure.
- `DSNoticeRow` for a permission or error plus an optional action.
- `DSEmptyState` when a collection has no content.

Platform-native `List`, `Form`, `Picker`, `TextEditor`, alerts, and standard
buttons are valid exceptions when they are not restyled into a new visual
component. The hidden Developer page is intentionally utilitarian and exempt.

## Review

Check each changed surface in light and dark appearance, increased contrast,
reduced motion, keyboard navigation, and the minimum supported window size.
Add a preview or Developer-gallery state when a shared component gains a new
normal, selected, disabled, loading, permission, error, or destructive state.
The `PlumaUITests` target covers real-window navigation and keyboard paths; it
is intentionally separate from the headless unit-test scheme because macOS UI
testing requires an unlocked interactive login session.
