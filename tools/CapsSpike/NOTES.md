# CapsSpike — findings

Standalone harness notes for Caps Lock as pluma’s shortcut modifier.

## Mechanism chosen

**A — inert alias (Caps → F18 via `hidutil`) + HID `CGEventTap`.**

Priority from the plan:

| Candidate | Result |
|---|---|
| **C — no alias / force caps state off** | Not shipped. Issue #23 already showed Caps toggle/LED is applied before taps; synthetic anti-toggle reverted. Skipping as primary. |
| **A — Caps → F18** | **Chosen.** Same structural approach as open Hyperkey clones; Hyperkey on this Mac aliases Caps to Right Command (`capsLockKeycode=231`) then expands flags — F18 is the safer inert alias (does not steal physical Right ⌘). |
| **B — Right Command alias** | Rejected for pluma: cannot distinguish aliased Caps from real Right ⌘. |

## Observe (Hyperkey ON vs OFF)

From `~/Library/Preferences/com.knollsoft.Hyperkey.plist` (2026-08-13):

- Caps physical keycode 57
- Aliased to keycode 231 (Right Command) when `keyRemap=1`
- `hyperFlags` on disk: `1835008` = ⌃⌥⌘; June backup had `1966080` = ⌃⌥⌘⇧
- Global `hidutil UserKeyMapping` is null — Hyperkey uses per-service / in-app mapping

Live event logging belongs in a future CapsSpike UI run with Input Monitoring; pluma embeds the same stack.

## Reliability

Hyperkey’s tap dies on wake/lock (`hyperkey-rearm.py`). pluma’s `CapsLockExpander` re-enables on `tapDisabled*` and reevaluates on wake / screens-wake / lock / unlock.

## Physical checklist (for Scott)

With Hyperkey quit and Settings → **Use Caps Lock for shortcuts** on:

1. Caps+E fires rewrite; no LED / no caps state
2. Lone Caps tap does nothing
3. Ordinary typing unchanged when Caps not held
4. Caps+Space press/release for dictation
5. Sleep/wake / lock — still works without relaunch
6. Toggle off restores normal Caps; quit clears HID remap
