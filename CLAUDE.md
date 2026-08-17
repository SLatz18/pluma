# pluma — agent notes

Native macOS writing tool (**pluma** / formal **plumafina**): recipe pipelines
(Rewrite page), ghost-text autocomplete, push-to-talk dictation,
selection-rewrite hotkey, on-device Reader. SwiftUI + AppKit, Swift 6 strict
concurrency, macOS 26 target, xcodegen-generated project. Product principles:
README.md. Privacy model: PRIVACY.md. Product language: native controls,
generous spacing, trigger → action cards.

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
  grants and Keychain ACLs survive rebuilds. Keep it.
- Install: `ditto DerivedData/Build/Products/Debug/Pluma.app ~/Applications/Pluma.app`
  (`/Applications` needs admin; `~/Applications` behaves identically).
- **Once Pluma has a Developer ID (or Apple Development team):** migrate
  `Services/KeychainStore.swift` from the file-based keychain to the data
  protection keychain (`kSecUseDataProtectionKeychain` +
  `keychain-access-groups` entitlement authorized by a provisioning profile).
  Self-signed builds get `errSecMissingEntitlement (-34018)` on that path, so
  today's file-based store is intentional — but it uses ACL prompts when the
  signing leaf hash changes. Data protection has no ACLs, so reads stay silent
  across updates. Also update `OpenAIKey`'s process cache comment (it
  currently papers over those prompts). See Apple TN3137.

## Architecture map

- `App/PlumaApp.swift` — builds shared `SuggestionOverlayController` and
  injects it into all presenters. One overlay panel, owner-scoped hides.
- `DesignSystem/` — semantic tokens, feature definitions, shared surfaces,
  WHEN → THEN → RESULT flow, and overlay presentations (`DS.*`).
- `Views/MainWindowView.swift` — the single window (`Window` scene, no
  Settings scene). Sidebar: Overview / Rewrite / Autocomplete / Dictation /
  Reader, then a Settings group (General / AI / Writing / Privacy, rendered by
  `SettingsPageView`) + Developer when unlocked. `MainNavigation.shared` is
  the one selection plus contextual focus/return route; ⌘,, the menu bar
  Settings… item, and `DSSharedSettingLink` all route through it.
- `Views/AISettingsContent.swift` — the editable AI control center. Provider,
  model, and voice controls bind directly to `RewriteViewModel`,
  `DictationController`, and `ReaderController`; never mirror their selection
  state. Feature-local controls may remain when they use those same bindings.
- `Services/OpenAICredentials.swift` — the sole observable OpenAI credential
  presence/validation state. The secret itself stays in Keychain and engines
  read it only at request time. Views must not add local `hasKey` state or a
  second key editor.
- `Providers/RewriteRunner.swift` — chain runner. The `@MainActor` variant
  reports progress; the nonisolated variant exists because the macOS Services
  handler blocks its thread on a semaphore (a MainActor hop would deadlock).
- `Hotkey/HotkeyManager.swift` — slot-based Carbon hotkeys
  (`.rewriteSelection`, `.dictation`, `.clipboardRewrite`, `.readSelection`),
  press+release for push-to-talk.
- `Hotkey/GlobalShortcut.swift` — factory chords ⇪E / ⇪Space / ⇪L; Caps chord is
  ⌃⌥⌘ or ⌃⌥⌘⇧; `conflicts(with:)` treats both as the same physical Caps press.
- `Hotkey/CapsLockExpander.swift` — optional in-app Caps Lock modifier (HID
  Caps→F18 + HID CGEventTap + wake/lock re-arm). Settings: Use Caps Lock for
  shortcuts; Caps chord with/without Shift. Auto-pauses when Hyperkey/Superkey
  runs. Product language is Caps, never “hyper.”
- `Reader/` — on-device `AVSpeechSynthesizer`; selection then clipboard;
  never reads `AXSecureTextField`.
- `Services/Preferences.swift` — all UserDefaults keys + one-time migrations.
- `Services/SyntheticEventMarker.swift` — EVERY synthetic keystroke Pluma
  posts (Reader’s ⌘C, paste-fallback ⌘V) must be marked, and every Pluma tap
  or global monitor must skip marked events. Unmarked self-events get the
  Caps chord ORed onto them (⌘C→Hyper-C while ⇪L is held) and wipe
  dictation’s spacing memory via the edit monitor. Note the expander sets no
  real modifier flags, so “wait for chord release” must poll
  `CapsLockExpander.shared.isCapsChordHeld`, not `CGEventSource.flagsState`.
- Open issues: #23 (Caps Lock expander history; in-app Caps shortcuts address
  the missing alias layer), #24 (developer mode, cheat-code unlock).

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
- A **closure literal written inside a `@MainActor` type inherits that
  isolation**, even when its body touches nothing isolated. Passed as a
  `@convention(c)` callback it compiles clean, then traps at runtime on any
  other thread (`swift_task_isCurrentExecutorWithFlags` →
  `dispatch_assert_queue_fail`, SIGTRAP). Write C callbacks as **file-scope
  functions**. Verify: the symbol's disassembly must contain no
  `isCurrentExecutor` call (`otool -tvV <binary> -p <mangled>`).
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

## Git conventions for agents in this repo

Read intent, not the literal command name — requests describe outcomes.

- **"rebase" / "rebase main" / "rebase the local repo" means SYNC**, not
  `git rebase`. Do `git fetch origin && git merge --ff-only origin/main`.
  Never run an actual rebase — merging is always the safe path here; rebases
  rewrite history and are the most common way work gets lost.
- "merge it here first" = merge locally and verify (build + tests + launch the
  app) before anything reaches the remote.
- Confirm before, not after, any history rewrite. If the literal reading is
  destructive and the intent reading is safe, take the safe one and say so.
- Destructive set — surface it and get an explicit yes: `push --force`,
  `rebase` on shared history, `reset --hard`, `branch -D`, `clean -fd`.
  Everything else is reflog-recoverable for ~90 days; when asked whether work
  was lost, prove it (`git diff <discarded> HEAD`) rather than just asserting
  it.
- Uncommitted work is the ONLY unrecoverable state. Commit before a session
  ends, and commit freely on feature branches without being asked.
- **Name branches, commits, and PRs for what pluma does**, not for another
  app's brand. Using Safari/Finder/Notes as an internal reference while
  designing is fine; putting those names in `feat/…`, commit subjects, or
  PR titles reads like imitation. Prefer outcome names
  (`feat/pinned-settings-sidebar`, "Adopt a native unified toolbar…") over
  reference names (`feat/safari-chrome`).
