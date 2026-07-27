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
- Cross-app rewriting uses the macOS Services system.
- Cross-app autocomplete uses the Accessibility API (Cotypist-style), so the
  app is no longer sandboxed or Mac App Store compatible.
- A copy → hotkey → paste fallback reaches apps whose text is not exposed
  through Accessibility.

## Current milestone

The app window is organized into three sidebar pages — **Rewrite** (pick a
recipe and try it on your own text), **Autocomplete**, and **Dictation** —
with model and style-profile settings under ⌘,.

- Four rewrite recipes: Improve, Shorten, Fix Grammar, and Professional.
- An IFTTT-style pipeline builder: tap recipes to stack them in run order
  (⇪E → Fix Grammar → Shorten → …). Each step runs its own tuned prompt and
  feeds the next; the same pipeline drives the playground and the hotkey.
- A built-in editor for trying each recipe on your own text.
- Live Apple Intelligence availability state.
- Optional Ollama discovery at `http://127.0.0.1:11434`.
- A global **Rewrite selection** hotkey — **Caps Lock E** by default (via
  Hyperkey), re-recordable in the app to any combo — that rewrites the
  current selection in any app via the Accessibility API.
- **Autocomplete everywhere**: debounced ghost-text completions at the caret in
  other apps' text fields, powered by the same on-device provider. **Tab**
  accepts the next word, **Shift-Tab** accepts the whole suggestion, **Escape**
  dismisses. Requires Accessibility access; the app lives in the menu bar with
  no Dock icon, and the icon only appears while a window is open.
- **Dictate anywhere**: hold **Caps Lock Space** and talk; let go and your words
  land at the caret in any app. Speech is transcribed by Apple's on-device
  model, then tidied from spoken to written form by your selected writing
  model. Requires microphone and Accessibility access.
- A universal **copy → hotkey → paste** fallback
  (**Control-Option-Shift-Command-E**) for editors whose selected text is not
  exposed through Accessibility, with a local change-summary HUD and Undo.

## Dictation notes

- Push-to-talk only: recording runs while the shortcut is held, so the
  microphone is never left open. A tap shorter than 300 ms is treated as a
  mis-press.
- A floating HUD near the caret shows the live transcript as you speak. Nothing
  is inserted until you release the key, so partial guesses never reach your
  document.
- **Context-aware transcription**: with screen context enabled, Rewrite OCRs
  the frontmost window and feeds the names and unusual terms it finds to the
  speech model as recognition bias, so people and products visible on screen
  transcribe correctly. The microphone opens first and the audio stream buffers
  while the OCR runs, so no speech is lost waiting for it.
- **Clean up with AI** removes filler words and false starts and fixes
  punctuation, keeping your wording and meaning. It is deliberately
  conservative and never answers or summarizes the transcript. If it fails,
  times out, or returns nothing, the raw transcript is inserted instead —
  dictation never costs you your words. Transcripts under three words skip the
  cleanup round trip.
- The shortcut is **Caps Lock Space** by default, which works because
  [Hyperkey](https://hyperkey.app) expands Caps Lock into ⌃⌥⌘ before any app
  sees the event. Rewrite deliberately does not remap Caps Lock itself: doing
  so would seize the key system-wide, disable its toggle and LED, and reset on
  every reboot. Without Hyperkey (or an equivalent), record any ordinary chord
  instead via **Change…**.
- Speech never leaves the Mac, and audio is not written to disk.

## Autocomplete notes

- Completion works from any caret position with no selection, using the text
  before the caret as context (minimum 16 characters).
- Suggestions insert via the Accessibility API, so they work in most native
  apps (AppKit, most Electron and browser fields) but not everywhere — apps
  that don't expose text via Accessibility (some custom editors) won't get
  suggestions.
- Typing text that matches the start of a suggestion trims it instead of
  dismissing it, so accepting word-by-word stays smooth.
- Optional **screen context**: with Screen Recording access granted, Rewrite
  OCRs the frontmost window (on-device, in real time) so completions can match
  what you are replying to — names, topics, tone. Off by default; nothing is
  stored.
- macOS blocks password fields from the Accessibility API automatically; no
  suggestion ever appears there.
- The app requests Accessibility access on first enable. Because Accessibility
  and App Sandbox are mutually exclusive, the sandbox entitlement was removed;
  the hardened runtime remains.

## Requirements

- macOS 26 or later.
- Xcode 26 or later.
- Apple Intelligence enabled and its on-device model downloaded.
- For dictation: a supported language for Apple's `SpeechTranscriber`. The model
  downloads itself on first use and adds nothing to the app bundle.
- Optional: [Hyperkey](https://hyperkey.app) for the default Caps Lock
  shortcuts (⇪E rewrite, ⇪Space dictation).
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
2. Open Rewrite once and grant Accessibility access.
3. Select editable text in another Mac app.
4. Press **Caps Lock E** (or your recorded shortcut).

The hotkey is registered by the app itself and the rewrite happens through
the Accessibility API, so the shortcut is configured in the app window —
**Change…** on the Rewrite page's "Rewrite the selection" card records
any combo, Hyperkey chords included. The **Edit with Rewrite** macOS Service remains available
from the right-click Services menu as a fallback for apps where
Accessibility insertion misbehaves; it no longer has a default shortcut, so
assign one in Keyboard Settings only if you want it.

### Universal flow (Google Docs, Electron apps, anything)

1. Select text and press **Command-C** yourself.
2. Press **Control-Option-Shift-Command-E** (hyperkey + E).
3. The HUD shows what changed; press **Command-V** to paste the correction.

The universal flow sidesteps Accessibility limitations: your own copy and
paste cross the app boundary, so it can work in canvas-rendered editors.

## Privacy

Apple Intelligence requests use Apple's Foundation Models framework and stay
on the Mac. Ollama requests go only to the loopback address. Rewrite does not
include analytics, an account system, or a remote API.

Autocomplete reads the text of the field you are actively typing in — only
while autocomplete is enabled, only the current field, and only to build the
completion prompt. Field text is held in memory for the active suggestion and
is never written to disk or sent anywhere. Password fields are unreadable by
design.

Screen context (optional) captures the frontmost window at the moment a
completion is requested and extracts visible text with on-device OCR. The
image and extracted text live only for that one request; neither is written
to disk, logged, or transmitted. Declining the permission keeps autocomplete
fully functional with field text only.

Style memory (optional, off by default) records only the suggestion text you
accept — never raw keystrokes and never screen contents — into a local JSON
file (`~/Library/Application Support/Rewrite/writing-memory.json`, capped at
300 entries). Recent phrases are fed back to the model so suggestions drift
toward your vocabulary. Clear it any time from the Autocomplete page.

Style profile (optional) imports a writing-style guide — for example a
SKILL.md another AI wrote about your voice — from Settings → Advanced. YAML
frontmatter is stripped on import, the text is stored locally
(`~/Library/Application Support/Rewrite/style-profile.md`, capped at 3,000
characters), and it guides completions until cleared.

Dictation records only while you hold the shortcut. Audio is transcribed by
Apple's on-device speech model and is never written to disk or transmitted.
The transcript is held in memory for the one insertion; when cleanup is on it
is passed to your selected writing model, which is Apple Intelligence
on-device by default, or Ollama on the loopback address if you chose it.
