# Security Policy

pluma is a high-privilege macOS app: it can use Accessibility, optional
Screen Recording, and the microphone. Treat trust issues seriously.

## Supported versions

Please report issues against the current `main` branch. Pre-1.0 releases are
experimental; fixes land on `main` first.

## What to report

- Unexpected network access or data leaving the Mac when local providers are
  selected
- Keychain / API-key handling bugs
- Accessibility, event-tap, or pasteboard misuse that could leak content
- Supply-chain concerns in build scripts or CI

## How to report

Please use GitHub’s
[private vulnerability reporting](https://github.com/SLatz18/pluma/security/advisories/new)
when available. If that is disabled, open a private security advisory request
or contact the maintainer through GitHub.

Do not file public issues for exploitable bugs until a fix is available.

## Non-goals

Feature requests, Accessibility false positives in specific apps, and model
quality issues belong in normal GitHub issues — not here.
