# Rewrite for Mac

Rewrite is a small, native macOS writing tool. Select text in almost any Mac
app, run **Edit with Rewrite**, and the selection is replaced with a cleaner
version. Or copy text anywhere — including Google Docs — press the global
hotkey, and paste the correction back.

This repository uses **Rewrite** as a working product name. It is intentionally
easy to rename before release.

## Product principles

- One obvious job: improve selected text.
- Apple Intelligence is the default and runs entirely on-device.
- Ollama is an optional local fallback. There is no cloud backend or account.
- The interface uses native macOS controls, generous spacing, and simple
  trigger-to-action cards inspired by IFTTT applets.
- Cross-app editing uses the macOS Services system plus a sandbox-legal
  copy → hotkey → paste flow, keeping the app compatible with App Sandbox
  and the Mac App Store.

## Current milestone

- Four rewrite recipes: Improve, Shorten, Fix Grammar, and Professional.
- A built-in playground for trying each recipe.
- Live Apple Intelligence availability state.
- Optional Ollama discovery at `http://127.0.0.1:11434`.
- A macOS Service named **Edit with Rewrite** with a default
  **Shift-Command-E** shortcut.
- A universal **copy → hotkey → paste** flow (Control-Option-Shift-Command-E)
  that works in apps where Services cannot reach the text, such as Google
  Docs. Uses Carbon's `RegisterEventHotKey` — no Accessibility permission
  required. *(New on `feat/hotkey-flow-and-hud`.)*
- A change-summary HUD after hotkey rewrites: what changed (computed from a
  local word-level diff, never model claims), with one-click Undo. The panel
  never steals focus. *(New on `feat/hotkey-flow-and-hud`.)*
- App Sandbox and network-client entitlements suitable for a future Mac App
  Store build.

## Requirements

- macOS 26 or later.
- Xcode 26 or later.
- Apple Intelligence enabled and its on-device model downloaded.
- Optional: [Ollama](https://ollama.com/) with at least one local model.

## Build

```sh
brew install xcodegen
./scripts/bootstrap.sh
open Rewrite.xcodeproj
```

Re-run `./scripts/bootstrap.sh` after pulling branches that add or remove
source files — `Rewrite.xcodeproj` is generated, not committed.

Or build from Terminal:

```sh
xcodebuild \
  -project Rewrite.xcodeproj \
  -scheme Rewrite \
  -configuration Debug \
  -derivedDataPath DerivedData \
  build
```

## Use it in other apps

### Services flow (native apps: Mail, Notes, Messages, …)

1. Build and copy `Rewrite.app` into `/Applications`.
2. Open Rewrite once.
3. Select editable text in another Mac app.
4. Press **Shift-Command-E**, or right-click and choose
   **Services → Edit with Rewrite**.

### Universal flow (Google Docs, Electron apps, anything)

1. Select text and press **Command-C** yourself.
2. Press **Control-Option-Shift-Command-E** (hyperkey + E).
3. The HUD shows what changed; press **Command-V** to paste the correction.

macOS lets people change the Services shortcut under **System Settings →
Keyboard → Keyboard Shortcuts → Services → Text**. Because macOS invokes the
Service inside the current app, Rewrite receives and replaces the selection
without Accessibility permission — where the app exposes its text at all.
The universal flow sidesteps that limitation entirely: your own copy and
paste cross the app boundary, so it works in canvas-rendered editors like
Google Docs.

## Privacy

Apple Intelligence requests use Apple's Foundation Models framework and stay
on the Mac. Ollama requests go only to the loopback address. Rewrite does not
include analytics, an account system, or a remote API.
