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

Use semantic macOS colors and SF Symbols. Outside the documented platform-native
exceptions below, do not introduce a raw feature color, corner radius, type
size, locally constructed card, badge, or pill in a user-facing view.

## Page composition

Feature pages use `DSFeaturePage`, which supplies the shared header and
WHEN → THEN → RESULT flow. Put feature-specific controls below it.

There is one window and one navigation. Settings are ordinary sidebar pages
(General, Writing, Privacy — a "Settings" sidebar group rendered by
`SettingsPageView`), not a second window; ⌘, and the menu bar's Settings…
select the General page. Shared writing, context, style, and privacy settings
appear once on those pages and are referenced from features with
`DSSharedSettingLink`, which navigates the sidebar to the page it names.

The boundary is strict in both directions: anything that configures a single
feature — including every one of its shortcuts — lives on that feature's page,
never on a settings page; settings pages hold only cross-feature concerns (app
behavior, Caps Lock, shared writing model and context, privacy). A feature's
display name comes from `FeatureDefinition.name` and is the same string in the
menu bar, the page hero toggle, and the Overview card — surfaces may add
detail (a shortcut hint) but never rename the feature.

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

Non-activating overlays that must remain outside SwiftUI's display cycle are a
documented AppKit exception. The autocomplete pill and rewrite-feedback HUD may
use `NSPanel`, `NSVisualEffectView`, and native AppKit controls because hosting
these transient surfaces in SwiftUI previously caused display-cycle constraint
re-entry crashes. These overlays must still use semantic system colors and
native controls, remain non-activating, and preserve keyboard and accessibility
behavior. Renderer-specific AppKit geometry and type metrics may remain local
when they are not reusable by SwiftUI surfaces. Keep each exception explicitly
allowlisted in `scripts/check-design-system.sh` so new AppKit visual primitives
still fail CI.

## Review

Check each changed surface in light and dark appearance, increased contrast,
reduced motion, keyboard navigation, and the minimum supported window size.
SwiftUI reveal animations must use `DS.Motion.reveal(reduceMotion:)` with the
view's `@Environment(\.accessibilityReduceMotion)` value; AppKit overlays
consult `DS.Motion.reduceMotion` so both go instant when the user turns
motion effects off.
Add a preview or Developer-gallery state when a shared component gains a new
normal, selected, disabled, loading, permission, error, or destructive state.
The `PlumaUITests` target covers real-window navigation and keyboard paths; it
is intentionally separate from the headless unit-test scheme because macOS UI
testing requires an unlocked interactive login session.
