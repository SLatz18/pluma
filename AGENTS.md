# AGENTS.md

Agent-oriented architecture notes and toolchain traps live in
[CLAUDE.md](CLAUDE.md). Read it first — it is the primary guide for working in
this codebase.

## Cursor Cloud specific instructions

**Platform reality: pluma is a native macOS 26 app and cannot be built or run
on the Linux Cloud Agent VM.** The app is an `xcodegen`-generated Xcode project
(`Pluma.xcodeproj`) that compiles with `xcodebuild` and imports macOS-only Apple
frameworks (AppKit, SwiftUI, `FoundationModels`, ScreenCaptureKit, Speech,
Vision, AVFoundation, `Carbon.HIToolbox`, ServiceManagement, Security,
ApplicationServices). None of `swift`, `xcodebuild`, `xcodegen`, or `brew` exist
on this Linux VM, and the frameworks only ship in the macOS SDK. This is a
platform incompatibility, not a missing dependency — no install step fixes it.

- **Full build / test / run requires macOS 26 + Xcode 26.** Do those on a Mac
  using the commands in `README.md` / `CLAUDE.md` (`./scripts/bootstrap.sh`,
  then `xcodebuild ... build|test`). The GitHub `Full build and test (macOS)`
  workflow (`.github/workflows/ci-full.yml`, `runs-on: macos-26`) is the
  authoritative full pipeline; it is `workflow_dispatch`-only today.

- **What IS runnable on the Linux VM** is exactly the `ubuntu-latest` job in
  `.github/workflows/ci.yml` — the cheap text-level checks. All three pass here
  with only `python3`, `rg`, and `git` (all preinstalled):
  - `./scripts/check-design-system.sh` — design-system drift check (needs `rg`).
    Diffs against a base ref; on a feature branch it compares to `main`.
  - plist validation — parse `Pluma/Info.plist`, `Pluma/PrivacyInfo.xcprivacy`,
    `Pluma/Pluma.entitlements` with Python `plistlib` (the Linux stand-in for
    macOS `plutil -lint`).
  - `python3 scripts/validate-shipping.py` — enforces the privacy/Service
    contract by scanning the Swift source and plists (no analytics SDKs, Ollama
    stays on loopback, Service contract shape, privacy manifest, entitlements).

- **No dependencies to install for the Linux checks.** `python3`, `rg`, and
  `git` are already present, so the startup update script is essentially a
  no-op guard that ensures `rg` exists (mirrors `ci.yml`).

- **Swift edits can only be validated for text/CI concerns here** (design-system
  drift, privacy/shipping metadata). Anything requiring compilation, tests, or
  running the app must be verified on macOS.
