# PLAN: Caps+4 opens macOS Spotlight clipboard history

Branch `feat/clipboard-history-hotkey`. Written before any code, per charter.

## Settled premise (not re-litigated)

macOS exposes no bindable clipboard-history action. Evidence is in
`ai_organization/cos/SOLUTION-clipboard-hotkey.md` (full `DefaultShortcutsTable.xml`
parse, `CGSGetSymbolicHotKeyValue` sweep of IDs 0-4095, Spotlight `openURLs:`
disassembly, ActionKit action inventory, all 8 Services groups). The only route is
synthesize `⌘Space`, then `⌘4`. This plan implements that route and nothing else.

## Approach

Ride the existing Carbon hotkey stack rather than touching the event tap.

Pluma's Caps layer already works in two halves: `CapsLockExpander`'s tap ORs
`⌃⌥⌘` onto a keystroke and **passes it through**, then a Carbon
`RegisterEventHotKey` registration consumes it. Five chords already prove the
mechanism (⇪E, ⇪Space, ⇪R, ⇪L, ⇪D). So "make Pluma consume Caps+4" means
**register slot 6 for the Caps chord + `4`** — not intercept in the tap.

This is why the approach was chosen over the two alternatives:

- **Rejected: consume inside `capsTapCallback`.** Would need a new dispatch
  path out of the tap thread, and would violate constraint 1 by construction.
  The Carbon handler already runs on the main Carbon event dispatcher, off the
  tap thread, so constraint 1 is satisfied *structurally* rather than by
  discipline.
- **Rejected: a separate `NSEvent` global monitor.** Global monitors observe
  but cannot consume, so `⌃⌥⌘4` would still leak to the focused app.

## Ponytail ladder

Checked the cheaper rungs first; every rung below is reuse, not new code.

| Need | Cheapest existing thing | New code? |
|---|---|---|
| Consume the chord | `HotkeyManager` + `GlobalShortcut` (5 chords already) | no — add slot 6 |
| Dispatch off the tap thread | Carbon dispatcher, already used by all 5 slots | no |
| Mark synthetic events | `Services/SyntheticEventMarker.swift` **already exists** | no |
| Tap ignores marked events | `CapsTapState.verdict` line 122 **already** returns `.passUnmodified` | no |
| Post a synthetic chord | `LiveReaderTextProvider.postCopyShortcut()` pattern | copy the shape |
| Wait for held Caps/modifiers | `waitForShortcutModifiersToRelease()` pattern + `CapsLockExpander.shared.isCapsChordHeld` | copy the shape |
| Re-register on settings change | `.capsShortcutsSettingsDidChange` + `ClipboardRewriteController` lines 58-64 | no |
| Add file to the build | `xcodegen generate` globs folders | no pbxproj edit |
| Spotlight open/ready signal | `CGWindowListCopyWindowInfo` (no new dependency, no new TCC grant) | small probe |

Net new: **one file**, plus a slot enum case, a factory chord, a conflict-list
row, and one start line. No settings subsystem (see Configurability below).

## Spotlight readiness signal (constraints 3 and 4 with one primitive)

`com.apple.Spotlight` (pid 2174 here) is **always resident**, so process presence
proves nothing. Measured the real signal read-only on this machine with Spotlight
**closed**:

- On-screen window list: **zero** Spotlight-owned windows.
- Full list (incl. off-screen): three windows exist — 64x64 at layer 0, 844x607
  at layer 23, and 640x56 at layer 23 with **alpha 0.0**. None on-screen.

So: **Spotlight is open iff it owns an on-screen window with alpha > 0 and width
≥ 200.** One predicate answers both "is it already open" (constraint 4) and "is
it ready yet" (constraint 3). Design details:

- Match by **PID** from `NSRunningApplication(bundleIdentifier: "com.apple.Spotlight")`,
  never by `kCGWindowOwnerName`. Window *names* require Screen Recording; owner
  PID, bounds, alpha and on-screen state do not. No new TCC grant.
- **Width ≥ 200, not layer == 23.** A layer number is the kind of constant that
  moves across an OS update; the width threshold cleanly excludes the 64x64
  window and survives a re-layer.
- Poll at 25 ms to a **1 s deadline**. No fixed sleep anywhere.

### Fail-safe on the one branch I cannot test

The closed state was measured, so the **false-positive** direction is ruled out
empirically: with Spotlight closed the predicate is false, so the code can never
skip `⌘Space` and fire a stray `⌘4` into a focused app. The **false-negative**
direction (predicate broken while Spotlight really is open) is unverified without
opening Spotlight on Scott's live session, which I am deliberately not doing.

I make that branch harmless by design: **on readiness timeout, log and bail — do
not send `⌘4`.** Worst case is "Spotlight opened, no history panel," dismissed
with Escape, with the cause in `DebugLog`. Strictly better than a fixed sleep,
which fires `⌘4` blind.

## Files

**New**
- `Pluma/Hotkey/ClipboardHistoryController.swift` — the whole feature:
  `SpotlightPresence` probe + `SpotlightPresenceProbing` protocol, the pure
  `ClipboardHistoryPlan` decision, and the `@MainActor` controller.

**Modified**
- `Pluma/Hotkey/HotkeyManager.swift` — `case clipboardHistory = 6`.
- `Pluma/Hotkey/GlobalShortcut.swift` — `clipboardHistoryDefault` (⇪4).
- `Pluma/Services/Preferences.swift` — `ShortcutOccupant.clipboardHistory` +
  one `conflictMessage` row.
- `Pluma/App/AppDelegate.swift` — one start line.
- `Pluma/App/PlumaApp.swift` — XCTest guard (see Risks).
- `PlumaTests/ClipboardHistoryControllerTests.swift` — new tests.
- `Pluma.xcodeproj` — regenerated by `xcodegen generate` *after* writes land.

## How each of the four constraints is met

1. **Dispatch outside the tap callback** — structural. The Carbon
   `kEventHotKeyPressed` handler runs on the main event dispatcher; the tap
   callback only ORs flags and passes the event through. Nothing is posted from
   inside `capsTapCallback`.
2. **Mark synthetic events** — two independent mechanisms, both named:
   (a) `SyntheticEventMarker.mark()` on every posted event; `CapsTapState.verdict`
   returns `.passUnmodified` at line 122, *before* the debounce block at line 132,
   so a synthetic keycode-4 cannot slide the debounce window either;
   (b) the synthetic `⌘4` carries only `.maskCommand`, never `⌃⌥⌘`, so Carbon
   cannot re-trigger slot 6 from it.
3. **Wait for readiness, no fixed sleep** — poll the on-screen-window predicate
   at 25 ms to a 1 s deadline, then bail rather than guess.
4. **Already-open Spotlight is not toggled closed** — probe first; if the
   predicate is already true, skip `⌘Space` entirely and send only `⌘4`.

Plus, as the brief requires: held Caps and other held modifiers are drained
first, by polling **both** `CGEventSource.flagsState(.hidSystemState)` and
`CapsLockExpander.shared.isCapsChordHeld` (the expander sets no real modifier
flags, so `flagsState` alone is blind to a live Caps hold — repo CLAUDE.md says
this explicitly). Deliberate duplication of Reader's helper rather than
refactoring Reader: this change should not touch the Reader path.

## Two things that would have shipped broken with green tests

- **`capsChordIncludesShift`.** A constant `⌃⌥⌘4` is a latent silent failure:
  `reevaluate()` sets `capsFlags` from that pref, so with it on the tap ORs
  `⌃⌥⌘⇧` and a registered `⌃⌥⌘4` never fires. Register with
  `GlobalShortcut.capsChordModifiers(includesShift:)` computed at registration
  time, and re-register on `.capsShortcutsSettingsDidChange`.
- **Instantiation.** `@StateObject(wrappedValue:)` autoclosures are lazy and
  SwiftUI re-inits `App` structs (repo CLAUDE.md). A UI-less controller added as
  a `@StateObject` may never be constructed — feature silently dead, tests green.
  So: `static let shared`, started explicitly from
  `AppDelegate.applicationDidFinishLaunching`, mirroring
  `CapsLockExpander.shared.startMonitoring()`.

## Configurability: hardcoded, and here is why

Not nearly free. The existing per-shortcut pattern costs 3 UserDefaults keys +
getter + setter + a `syncCapsChordShortcuts` entry + an occupant case + a
`conflictMessage` row + a `SettingsView` row + `ShortcutRecorderView` wiring —
roughly 7 touchpoints across two subsystems. The brief says hardcode and say so,
and not to build a settings subsystem. **Hardcoded to Caps+4.**

One exception, taken because it is genuinely 2 lines: add the `ShortcutOccupant`
case and the `conflictMessage` row. The repo's own comment says Carbon refuses a
duplicate chord and a collision leaves one feature "silently dead" — so recording
⇪4 for another feature should warn instead of quietly killing this one.

## Risks and one-way doors

- **`xcodebuild test` would mutate Scott's live keyboard — the real hazard here.**
  `PlumaTests` is `bundle.unit-test` with a dependency on `Pluma`, so XcodeGen sets
  `TEST_HOST` and the test run **launches Pluma.app**. `PlumaApp.init()` lines
  24-27 clear the HID Caps→F18 mapping **unconditionally**, before any
  enabled-check, and line 46 starts a **second** event tap. Running tests mid-day
  would drop Scott's Caps Lock key (the running instance self-heals within its 3 s
  poll, but that is luck, not design).
  **Mitigation:** gate both the crash-recovery clear and `startMonitoring()` on
  `ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil`.
  Four lines in `PlumaApp.swift`. This is a **deliberate addition outside the
  brief's named touchpoints** — surfaced here rather than smuggled in, because
  `build-for-testing` alone would not satisfy the brief's "tests passing."
  **Proof, not assertion:** snapshot `hidutil property --get "UserKeyMapping"`
  before and after the test run and diff.
  Not fixed, pre-existing, one line each in RESULT: the test host still registers
  a services provider and a second menu bar item, and still touches
  `MemoryStore`/`SpellMemoryStore`/`StyleProfileStore` on disk.
- **Reversible.** No TCC grant is reset (no new permission; signing identity
  unchanged, so grants survive), no system preference touched, no HID remap
  change, no binary swap. Everything is on a branch. `git branch -D` undoes it.
- **Not done, per the brief's hard stops:** no build-and-install, no `ditto` to
  `~/Applications`, no merge, no push, no other worktree touched.
- **Known unverifiable without running the app:** that Spotlight actually shows
  the history panel on `⌘4`, and the false-negative branch of the probe. Stated
  plainly in RESULT rather than claimed.

## Verification

1. `xcodegen generate` — after writes, not in parallel.
2. `hidutil property --get "UserKeyMapping"` → save as before-snapshot.
3. `xcodebuild -project Pluma.xcodeproj -scheme Pluma -configuration Debug -derivedDataPath DerivedData test` — real output pasted into RESULT.
4. `hidutil property --get "UserKeyMapping"` → diff against the before-snapshot; must be identical.
5. Caps+letter still works by hand (Scott's keyboard unchanged).
6. Tests, at minimum the two the brief names: the tap ignores its own synthetic
   events (and does not slide the debounce window), and an already-open Spotlight
   yields `.historyOnly` — never a `⌘Space` that would toggle it closed.
7. `git log --stat` on the branch; nothing outside the planned files.

## Open questions

None blocking. The two judgment calls I made rather than escalating, both
recorded above: the `PlumaApp.swift` XCTest guard (outside the brief's named
touchpoints, but the alternative is mutating Scott's keyboard), and declining to
open Spotlight on his live session to test the false-negative branch (made
harmless by the bail-on-timeout design instead).
