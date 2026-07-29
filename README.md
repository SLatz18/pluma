# Rewrite for Mac

**Native macOS writing assistance — on-device by default, cross-app by design.**

Select text anywhere and rewrite it. Get ghost-text completions as you type.
Hold a shortcut and dictate at the caret. Built in Swift 6 for macOS 26 with
Apple Intelligence first, optional local Ollama, and an optional OpenAI path
for dictation only.

[Privacy](PRIVACY.md) · [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [License](LICENSE)

> Status: **early open source (`0.1.x`)**. The core workflows work; polish,
> packaging, and app coverage are active work. Contributions welcome.

## Why this exists

Most writing tools either live inside one editor or ship your prose to a
cloud. Rewrite is an experiment in the other direction: a small resident Mac
app that meets you in whatever field you are already in, keeps the default
path on-device, and makes every permission and network hop explicit.

It is also a concrete showcase of modern macOS systems work — Accessibility,
Carbon hotkeys, ScreenCaptureKit OCR, Speech, Foundation Models, Keychain,
and a deliberate AppKit overlay — under Swift 6 strict concurrency.

## Features

| | |
|---|---|
| **Rewrite** | Stack recipes (Improve, Shorten, Fix Grammar, Professional) into a pipeline. Run it from a global hotkey or the in-app playground. |
| **Autocomplete** | Debounced ghost text at the caret in other apps. Tab = next word, Shift-Tab = all, Escape dismisses. |
| **Dictation** | Push-to-talk at the caret. On-device speech by default; optional cleanup; optional OpenAI transcription. |
| **Screen context** | Opt-in OCR of the frontmost window so names on screen bias dictation and completions. Nothing stored. |
| **Style memory** | Opt-in local phrases from accepted suggestions (capped). Clear anytime. |

Default hotkeys use Caps Lock chords via [Hyperkey](https://hyperkey.app)
(⇪E rewrite, ⇪Space dictate). Without Hyperkey, record any ordinary shortcut
in-app with **Change…**.

## Privacy in one screen

| Path | Leaves this Mac? |
|---|---|
| Apple Intelligence rewrite / complete / cleanup | No |
| Ollama at `127.0.0.1` | No (loopback only) |
| Apple Speech dictation | No |
| OpenAI dictation / cleanup (opt-in) | **Yes — only when you choose it** |
| Analytics / accounts / Rewrite servers | None |

Full detail: [PRIVACY.md](PRIVACY.md).

## Requirements

- macOS 26 or later, Xcode 26 or later
- Apple Intelligence on-device model (for the default provider)
- Accessibility permission for cross-app rewrite / autocomplete / insertion
- Microphone for dictation; Screen Recording only if you enable screen context
- Optional: [Hyperkey](https://hyperkey.app), [Ollama](https://ollama.com/), OpenAI API key

## Build

```sh
brew install xcodegen
./scripts/bootstrap.sh
open Rewrite.xcodeproj
```

Or from Terminal:

```sh
xcodebuild \
  -project Rewrite.xcodeproj \
  -scheme Rewrite \
  -configuration Debug \
  -derivedDataPath DerivedData \
  build
```

Install a debug build without needing admin rights:

```sh
ditto DerivedData/Build/Products/Debug/Rewrite.app ~/Applications/Rewrite.app
```

Signing uses a stable **Local Self-Signed** identity so Accessibility grants
survive rebuilds. Hardened runtime is off for that local identity (library
validation breaks the test bundle without a Developer ID). Distribution builds
should use Developer ID + hardened runtime + notarization — see
[CONTRIBUTING.md](CONTRIBUTING.md).

## Use it

1. Build and open Rewrite; grant Accessibility when asked.
2. Pick a recipe pipeline on the Rewrite page; try it in the playground.
3. Select text in another app → **Caps Lock E** (or your shortcut).
4. Enable Autocomplete / Dictation from their sidebar pages as needed.

**Edit with Rewrite** remains available as a macOS Service (right-click →
Services) for apps where Accessibility insertion misbehaves.

## Architecture

| Area | Role |
|---|---|
| `Providers/` | Apple Intelligence, Ollama, OpenAI chat; shared `RewriteRunner` |
| `Autocomplete/` | Focused-field tracking, caret probing, ghost-text overlay (AppKit) |
| `Dictation/` | Push-to-talk capture, Apple / OpenAI transcription, cleanup |
| `Hotkey/` | Slot-based Carbon hotkeys; Hyperkey-aware chord display |
| `Views/DesignSystem.swift` | Shared card / eyebrow / status grammar (`DS.*`) |
| `Services/Preferences.swift` | UserDefaults keys + migrations |

Agent-oriented notes and toolchain traps: [CLAUDE.md](CLAUDE.md).

## Contributing

Bug reports, app-coverage fixes, prompt/tests, and docs are the highest
leverage. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a PR —
especially the privacy house rules.

## License

[MIT](LICENSE) © 2026 Scott Latz
