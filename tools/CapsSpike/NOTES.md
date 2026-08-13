# CapsSpike — findings

Standalone harness notes for Caps Lock as pluma’s shortcut modifier.

## Mechanism chosen (proven on device 2026-08-13)

**A — inert alias (Caps → F18 via `hidutil`) + session `CGEventTap` + dual-role tap.**

| Candidate | Result |
|---|---|
| **C — no alias / force caps state off** | Not shipped. Issue #23 already showed Caps toggle/LED is applied before taps. |
| **A — Caps → F18** | **Chosen.** Safe inert alias; does not steal physical Right ⌘. |
| **B — Right Command alias** | Rejected: cannot distinguish aliased Caps from real Right ⌘. |
| **HID-level tap** | Rejected: requires Input Monitoring. Hyperkey uses a **session** tap (Accessibility only). |
| **Dual-role** | **Required.** Hold = modifier; quick lone tap = real Caps Lock via `IOHIDSetModifierLockState` (LED included). Consuming Caps alone made Caps Lock unusable. |

## Reliability (must-haves from review panel)

1. **Surgical hidutil clear** — remove only Caps→F18; never write `UserKeyMapping:[]`.
2. **Reset machine on `tapDisabled*`** + **max-hold ceiling (~2.5s)** — a lost Caps key-up must not OR ⌃⌥⌘ onto all typing.
3. **`CapsLockState.turnOff()` on teardown** + **Restore Caps Lock** Settings action.
4. **Dedicated run-loop thread** for the tap — never the SwiftUI main thread.
5. **Clear remap on screen lock**; re-apply on unlock/wake.
6. Probe real mapping with `--get`, not only in-memory `remapApplied`.

## Physical checklist

With Hyperkey quit and CapsSpike (or Pluma Caps shortcuts) started + Accessibility granted:

1. Caps+letter fires chord; no capitalization of that letter
2. Lone Caps tap toggles Caps Lock + LED
3. Ordinary typing unchanged when Caps not held
4. Sleep/wake / lock — still works without relaunch
5. Stop / quit restores Caps; other hidutil remaps (e.g. Caps→Esc) survive
6. Force-quit while enabled → relaunch or Restore Caps Lock recovers
