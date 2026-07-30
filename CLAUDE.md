# pluma — agent notes

Native macOS writing tool (**pluma** / formal **plumafina**): recipe pipelines
(Rewrite page), ghost-text autocomplete, push-to-talk dictation,
selection-rewrite hotkey. SwiftUI + AppKit, Swift 6 strict concurrency,
macOS 26 target, xcodegen-generated project. Product principles: README.md.
Privacy model: PRIVACY.md. Product language: native controls, generous
spacing, trigger → action cards.

## Build, test, install

```sh
xcodegen generate          # REQUIRED after adding/removing files; globs folders
xcodebuild -project Pluma.xcodeproj -scheme Pluma -configuration Debug \
  -derivedDataPath DerivedData build   # append `test` for tests
```

- `Pluma.xcodeproj` is generated — never hand-edit; edit `project.yml` or
  add/remove files and regenerate. Regenerate AFTER file writes land (parallel
  tool calls race it).
- Signing is the stable "Local Self-Signed" identity so Accessibility/TCC
  grants survive rebuilds. Keep it.
- Install: `ditto DerivedData/Build/Products/Debug/Pluma.app ~/Applications/Pluma.app`
  (`/Applications` needs admin; `~/Applications` behaves identically).

## Architecture map

- `App/PlumaApp.swift` — builds shared `SuggestionOverlayController` and
  injects it into all three presenters. One overlay panel, owner-scoped hides.
- `Views/DesignSystem.swift` — the one card/tile/eyebrow/status-row grammar
  (`DS.*`). New surfaces use it or they drift.
- `Views/MainWindowView.swift` — sidebar: Rewrite / Autocomplete / Dictation.
- `Providers/RewriteRunner.swift` — chain runner. The `@MainActor` variant
  reports progress; the nonisolated variant exists because the macOS Services
  handler blocks its thread on a semaphore (a MainActor hop would deadlock).
- `Hotkey/HotkeyManager.swift` — slot-based Carbon hotkeys
  (`.rewriteSelection`, `.dictation`), press+release for push-to-talk.
- `Hotkey/GlobalShortcut.swift` — factory chords ⇪E / ⇪Space via Hyperkey's
  ⌃⌥⌘ expansion; `conflicts(with:)` treats 3- and 4-modifier hyper chords as
  the same press.
- `Services/Preferences.swift` — all UserDefaults keys + one-time migrations.
- Open issues: #23 (Caps Lock expander post-mortem), #24 (developer mode,
  cheat-code unlock).

## Verification recipes that work here

- Screenshot loop: launch build, `screencapture -x /tmp/x.png`, Read the PNG.
- Drive the sidebar via System Events:
  `click row N of outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1`
- Live overlay test: launch app, open TextEdit, keystroke 40+ chars via
  System Events, wait ~2 s — the ghost-text pill appears below the caret.
- Synthetic hotkey e2e: post `CGEvent`s (caps down with `.maskAlphaShift`,
  then the letter) at `.cghidEventTap`; watch the status pill flash.
  NB: synthetic CAPS STATE is unreliable — see issue #23, wall 2.

## Toolchain traps (macOS 26 SDK + Swift 6) — cost real time

- `MainActor.assumeIsolated` inside a `CGEventTap` callback **crashes
  swift-frontend** (`SendNonSendable` pass, `Partition::merge`). No actor hops
  in C callbacks: use an `NSLock`-guarded nonisolated `@unchecked Sendable`
  state box.
- `@StateObject(wrappedValue:)` **autoclosures are lazy** — objects are built
  on first body access, not during init. Anything init-order-sensitive
  (logging, truncation, registration) must not assume init-time creation.
- SwiftUI **re-initializes `App` structs**; tap/hotkey-owning objects must be
  singletons or they double-register.
- Trailing closures never bind to **optional** closure parameters — pass the
  label explicitly (`onProgress: { ... }`).
- `NSAccessibilityReduceMotionEnabled()` is not exposed; use
  `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.
- `CGEventTapEnable` is now `CGEvent.tapEnable(tap:enable:)`; `CGEventFlags`
  option is `.maskAlternate` (not maskOption); Swift 6 `catch` must be
  exhaustive (`catch let e as X` needs a general `catch` too).
- `if/switch` expressions as implicit returns lose their contextual type if
  you add an early `return` above them — write `return switch`.

## House rules for changes

- Worktree + branch per chat (`git worktree add ../pluma-wt-<topic> -b
  feat/<topic> main`), merge to main after verification, remove the worktree.
- Tests run with `xcodebuild ... test`; keep them green before merging.
- The overlay is pure AppKit by deliberate choice (SwiftUI hosting crashed
  twice in display-cycle layout) — do not reintroduce a SwiftUI graph there.
- Privacy: transcripts/audio never persist; style memory and style profile
  are the only content stores, both opt-in. Preserve that in copy and code.
  See PRIVACY.md for the public privacy model (including optional OpenAI).

## Git vocabulary — Scott is not a git native

Read intent, not the literal command name. Scott describes outcomes.

- **"rebase" / "rebase main" / "rebase the local repo" means SYNC**, not
  `git rebase`. Do `git fetch origin && git merge --ff-only origin/main`.
  Never run an actual rebase — see "Rebase: don't" in projects/CLAUDE.md.
- "merge it here first" = merge locally and verify (build + tests + launch the
  app) before anything reaches the remote.
- Confirm before, not after, any history rewrite. If the literal reading is
  destructive and the intent reading is safe, take the safe one and say so.
- Destructive set — surface it and get an explicit yes: `push --force`,
  `rebase` on shared history, `reset --hard`, `branch -D`, `clean -fd`.
  Everything else is reflog-recoverable for ~90 days; say so when he asks
  whether work was lost, and prove it (`git diff <discarded> HEAD`) rather
  than just asserting it.
- Uncommitted work is the ONLY unrecoverable state. Commit before a chat ends,
  and commit freely on feature branches without being asked.
