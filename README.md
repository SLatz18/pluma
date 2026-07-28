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
- Cross-app rewriting uses the macOS Services system.
- Cross-app autocomplete uses the Accessibility API (Cotypist-style), so the
  app is no longer sandboxed or Mac App Store compatible.

## Current milestone

- Four rewrite recipes: Improve, Shorten, Fix Grammar, and Professional.
- A built-in playground for trying each recipe.
- Live Apple Intelligence availability state.
- Optional Ollama discovery at `http://127.0.0.1:11434`.
- A macOS Service named **Edit with Rewrite** with a default
  **Shift-Command-E** shortcut and support for a user-assigned Hyperkey chord.
- **Autocomplete everywhere**: debounced ghost-text completions at the caret in
  other apps' text fields, powered by the same on-device provider. **Tab**
  accepts the next word, **Shift-Tab** accepts the whole suggestion, **Escape**
  dismisses. Requires Accessibility access; the app stays alive in the menu
  bar after its window closes.

## Autocomplete notes

- Completion requires the caret to be at the end of the text with no selection,
  and at least 16 characters of context.
- Suggestions insert via the Accessibility API, so they work in most native
  apps (AppKit, most Electron and browser fields) but not everywhere — apps
  that don't expose text via Accessibility (some custom editors) won't get
  suggestions.
- Typing text that matches the start of a suggestion trims it instead of
  dismissing it, so accepting word-by-word stays smooth.
- macOS blocks password fields from the Accessibility API automatically; no
  suggestion ever appears there.
- The app requests Accessibility access on first enable. Because Accessibility
  and App Sandbox are mutually exclusive, the sandbox entitlement was removed;
  the hardened runtime remains.

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

Autocomplete reads the text of the field you are actively typing in — only
while autocomplete is enabled, only the current field, and only to build the
completion prompt. Field text is held in memory for the active suggestion and
is never written to disk or sent anywhere. Password fields are unreadable by
design.
