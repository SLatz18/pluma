# pluma (plumafina)

A native macOS writing layer — on-device by default, cross-app by design.
Select text anywhere and rewrite it. Get ghost-text completions as you type.
Hold a shortcut and dictate at the caret.

Built in Swift 6 for macOS 26 with Apple Intelligence first, optional local
Ollama, and an optional OpenAI path for dictation only.

## Stack

- **Language:** Swift 6 (strict concurrency)
- **Frameworks:** SwiftUI + AppKit, Foundation Models, Speech, Accessibility,
  ScreenCaptureKit
- **Target:** macOS 26+
- **Build tool:** xcodegen (`project.yml` → `Pluma.xcodeproj`)

## Building (requires macOS + Xcode)

```sh
xcodegen generate          # REQUIRED after adding/removing files
xcodebuild -project Pluma.xcodeproj -scheme Pluma -configuration Debug \
  -derivedDataPath DerivedData build
# Install (no admin needed):
ditto DerivedData/Build/Products/Debug/Pluma.app ~/Applications/Pluma.app
```

Run tests by appending `test` to the xcodebuild command.

> **Note:** This project cannot be built or run on Replit — it targets macOS
> and requires Xcode. Replit is used here as a code editor and storage.

## Project layout

| Path | Purpose |
|---|---|
| `Pluma/` | Main app source (Swift) |
| `PlumaTests/` | Unit tests |
| `PlumaUITests/` | UI tests |
| `Pluma.xcodeproj/` | Generated Xcode project — do not hand-edit |
| `project.yml` | XcodeGen spec — edit this instead of the .xcodeproj |
| `scripts/` | Build/utility scripts |
| `docs/` | Additional documentation |

## Key architecture areas

| Area | Role |
|---|---|
| `Providers/` | Apple Intelligence, Ollama, OpenAI; shared `RewriteRunner` |
| `Autocomplete/` | Focused-field tracking, caret probing, ghost-text overlay |
| `Dictation/` | Push-to-talk capture, Apple / OpenAI transcription, cleanup |
| `Hotkey/` | Slot-based Carbon hotkeys; Hyperkey-aware chord display |
| `DesignSystem/` | Tokens, components, overlay presentations |
| `Services/Preferences.swift` | UserDefaults keys + migrations |

See `CLAUDE.md` for agent-oriented notes and toolchain traps.

## User preferences

- Use Replit as a code editor and storage; no run workflow needed.
