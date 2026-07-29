# Contributing

Thanks for wanting to improve Rewrite. The project is early (`0.1.x`) and
welcomes focused pull requests more than drive-by refactors.

## Before you start

1. Read [PRIVACY.md](PRIVACY.md) — privacy behavior is part of the product.
2. Skim [CLAUDE.md](CLAUDE.md) for the architecture map and Swift 6 / macOS 26
   traps that have already cost real time.
3. Open an issue for large changes so direction stays aligned.

## Development setup

```sh
brew install xcodegen
./scripts/bootstrap.sh
open Rewrite.xcodeproj
```

Build and test:

```sh
xcodebuild \
  -project Rewrite.xcodeproj \
  -scheme Rewrite \
  -configuration Debug \
  -derivedDataPath DerivedData \
  test
```

After adding or removing source files, regenerate the project:

```sh
xcodegen generate
```

`Rewrite.xcodeproj` is generated — edit `project.yml` or the source tree, not
the pbxproj by hand.

## House rules

- **Privacy first.** Transcripts and audio must not persist. Style memory and
  style profile are the only content stores, both opt-in. Do not add analytics.
- **One job per PR.** Prefer small, reviewable changes with a clear test plan.
- **Keep tests green.** Add or update unit tests next to behavior changes when
  the logic is pure enough to test without Accessibility.
- **Use the design system.** New UI goes through `Views/DesignSystem.swift`
  (`DS.*`) so surfaces do not drift.
- **Overlay stays AppKit.** The suggestion / status overlay is deliberately not
  SwiftUI — do not reintroduce a SwiftUI hosting graph there.
- **No secrets.** Never commit API keys, certificates, or personal writing
  samples. Tests should use fictional fixtures.

## Good first contributions

- App coverage gaps (Electron / browser caret probing)
- Recipe / prompt quality with unit-tested composer changes
- Accessibility VoiceOver labels and keyboard paths
- Docs: screenshots, troubleshooting, Hyperkey alternatives
- Hardening: Ollama cloud-model guards, notarization scripts

## Pull request checklist

- [ ] `xcodegen generate` if files were added or removed
- [ ] Tests added or updated when behavior changed
- [ ] Privacy copy still matches the code path you touched
- [ ] No personal or employer-specific fixtures in tests
