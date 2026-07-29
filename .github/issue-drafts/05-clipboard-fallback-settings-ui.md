# Add Settings UI for clipboard fallback status and permissions

Suggested labels: `enhancement`, `ui`, `permissions`

## Summary

Extend the existing General settings tab with:

- Current clipboard-hotkey reliability state.
- An explicit action to enable optional Input Monitoring.
- Pasteboard privacy explanation.
- A link to Paste from Other Apps settings.

## Value relative to `main`

This UI has no standalone product value without the clipboard fallback.

If the fallback and optional enhanced listener are implemented, Settings is
necessary to make their behavior understandable. Otherwise users cannot tell
whether they are on the zero-permission Carbon tier, whether Input Monitoring
worked, or how to recover from denied pasteboard access.

The new controls must be merged into `main`'s existing tabbed Settings view
without removing Launch at Login, writing model, provider status, or Advanced
settings.

## Reference implementation

Available on branch `cloudai/finish-rewrite-e2e-5d52`:

- `Rewrite/Views/SettingsView.swift`
- `HotkeyStatus` and `ClipboardHotkeyManager` in
  `Rewrite/Services/ClipboardHotkeyManager.swift`
- `PasteboardAccess.openPrivacySettings()`

## Status model

```swift
struct HotkeyStatus: Equatable, Sendable {
    enum Tier: Equatable, Sendable {
        case unavailable
        case carbonOnly
        case enhanced
    }

    let tier: Tier
    let title: String
    let detail: String
    let symbolName: String

    static let unavailable = HotkeyStatus(
        tier: .unavailable,
        title: "Hotkey unavailable",
        detail: "Another app may be using the clipboard shortcut.",
        symbolName: "exclamationmark.triangle"
    )

    static let carbonOnly = HotkeyStatus(
        tier: .carbonOnly,
        title: "Standard hotkey",
        detail: "Works in most apps. Enhanced mode is optional.",
        symbolName: "keyboard"
    )

    static let enhanced = HotkeyStatus(
        tier: .enhanced,
        title: "Enhanced hotkey",
        detail: "Input Monitoring is enabled.",
        symbolName: "keyboard.badge.ellipsis"
    )
}
```

`ClipboardHotkeyManager` should conform to `ObservableObject` and publish
status changes:

```swift
@MainActor
final class ClipboardHotkeyManager: ObservableObject {
    static let shared = ClipboardHotkeyManager()

    @Published private(set) var status: HotkeyStatus = .carbonOnly
}
```

## SwiftUI integration

Preserve the current state and controls from `main`:

```swift
struct SettingsView: View {
    @EnvironmentObject private var model: RewriteViewModel
    @ObservedObject private var clipboardHotkeys =
        ClipboardHotkeyManager.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        TabView {
            Form {
                // Existing App and Writing model sections stay here.

                Section("Universal hotkey") {
                    LabeledContent("Reliability") {
                        Label(
                            clipboardHotkeys.status.title,
                            systemImage: clipboardHotkeys.status.symbolName
                        )
                        .foregroundStyle(hotkeyColor)
                    }

                    Text(clipboardHotkeys.status.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if clipboardHotkeys.status.tier != .enhanced {
                        Button("Enable Enhanced Hotkey…") {
                            clipboardHotkeys
                                .requestInputMonitoringAccess()
                        }
                    }
                }

                Section("Privacy") {
                    // Preserve existing provider privacy copy.
                    Text(
                        "The universal flow reads your clipboard " +
                        "only after you invoke its hotkey."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Button("Open Pasteboard Settings…") {
                        PasteboardAccess.openPrivacySettings()
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("General", systemImage: "gear")
            }

            AdvancedSettingsView()
                .tabItem {
                    Label("Advanced", systemImage: "brain")
                }
        }
        .task {
            await model.refreshStatus()
            clipboardHotkeys.refresh()
        }
    }
}
```

## UX requirements

- Call the feature a fallback or universal clipboard flow; do not imply it
  replaces Caps Lock E.
- Explain that Standard mode needs no extra permission.
- Explain why Enhanced mode requests Input Monitoring before prompting.
- Trigger the system permission request only from a user-clicked button.
- Show success after the user returns from System Settings.
- Make pasteboard and Input Monitoring permissions distinct.
- Do not present Accessibility, Input Monitoring, and Pasteboard access as the
  same permission.
- Keep text concise enough for the existing 560-point Settings window.

## Acceptance criteria

- Existing Settings sections and Advanced tab remain functional.
- Status updates when Carbon registration fails or enhanced mode activates.
- Enable Enhanced Hotkey requests Input Monitoring and opens the correct pane.
- Pasteboard Settings opens the correct privacy pane.
- Returning to Rewrite refreshes status without restarting the app.
- Controls have accessible labels and work with keyboard navigation.
- The Settings window does not grow beyond reasonable laptop display sizes.

## Tests

- Unit-test status titles, details, symbols, and tier transitions.
- SwiftUI preview or snapshot for each status if the project supports it.
- Manual tests for allowed, denied, and revoked permissions.
- Regression test Launch at Login and Advanced settings after merging.

## Dependencies

- Clipboard fallback issue.
- Pasteboard privacy issue.
- Optional enhanced hotkey issue for the Enhanced controls.
