# Rewrite for Mac

Rewrite is a small, native macOS writing tool. Select text in almost any Mac
app, run **Edit with Rewrite**, and the selection is replaced with a cleaner
version.

This repository uses **Rewrite** as a working product name. It is intentionally
easy to rename before release.

## Product principles

- One obvious job: improve selected text.
- Apple Intelligence is the default and runs entirely on-device.
- Ollama is an optional local fallback. There is no cloud backend or account.
- The interface uses native macOS controls, generous spacing, and simple
  trigger-to-action cards inspired by IFTTT applets.
- Cross-app editing uses the macOS Services system, keeping the app compatible
  with App Sandbox and the Mac App Store.

## Current milestone

- Four rewrite recipes: Improve, Shorten, Fix Grammar, and Professional.
- A built-in playground for trying each recipe.
- Live Apple Intelligence availability state.
- Optional Ollama discovery at `http://127.0.0.1:11434`.
- A macOS Service named **Edit with Rewrite** with a default
  **Shift-Command-E** shortcut and support for a user-assigned Hyperkey chord.
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

1. Build and copy `Rewrite.app` into `/Applications`.
2. Open Rewrite once.
3. Select editable text in another Mac app.
4. Press **Shift-Command-E**, or right-click and choose
   **Services → Edit with Rewrite**.

macOS lets people change the shortcut under **System Settings → Keyboard →
Keyboard Shortcuts → Services → Text**. To use Hyperkey, assign
**Control-Option-Shift-Command-E** to **Edit with Rewrite**. Because macOS
invokes the Service inside the current app, Rewrite receives and replaces the
selection without Accessibility permission. An app’s own shortcut wins if it
conflicts with the Service shortcut.

## Privacy

Apple Intelligence requests use Apple’s Foundation Models framework and stay
on the Mac. Ollama requests go only to the loopback address. Rewrite does not
include analytics, an account system, or a remote API.
