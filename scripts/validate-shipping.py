#!/usr/bin/env python3
"""Assert pluma's shipping metadata matches the privacy and Service contract.

Adapted from the version on archive/pr-22-hardening. That one encoded the
abandoned architecture: it forbade Carbon and CGEvent APIs and required the App
Sandbox, both of which contradict how pluma actually works now. main uses Carbon
hotkeys and Accessibility deliberately, so those assertions are gone.

What stays is the part that still protects the product: the privacy manifest
shape, the Service contract, and the promise that no analytics or tracking ever
ships. See PRIVACY.md.
"""

from pathlib import Path
import plistlib
import sys

ROOT = Path(__file__).resolve().parent.parent
FAILURES: list[str] = []


def check(condition: object, message: str) -> None:
    if not condition:
        FAILURES.append(message)


def load_plist(relative_path: str) -> dict:
    with (ROOT / relative_path).open("rb") as handle:
        return plistlib.load(handle)


# --- Privacy: no analytics or tracking may ever ship -------------------------
# PRIVACY.md promises no analytics and no accounts. These are the SDK names that
# would break that promise, so catch them at build time rather than in review.
swift_source = "\n".join(
    path.read_text(encoding="utf-8") for path in (ROOT / "Pluma").rglob("*.swift")
)
for forbidden in (
    "FirebaseAnalytics",
    "Mixpanel",
    "Amplitude",
    "Sentry",
    "AppCenter",
    "TelemetryDeck",
    "import AdSupport",
    "ASIdentifierManager",
    "import AppTrackingTransparency",
):
    check(forbidden not in swift_source, f"Analytics/tracking SDK referenced: {forbidden}")

# Ollama must stay on loopback. A non-loopback host here would silently send the
# writer's prose off the machine.
for suspicious in ("http://0.0.0.0", "ollama.com", "api.ollama"):
    check(suspicious not in swift_source, f"Non-loopback Ollama host referenced: {suspicious}")


# --- Service contract --------------------------------------------------------
info = load_plist("Pluma/Info.plist")
services = info.get("NSServices", [])
check(len(services) >= 1, "Info.plist declares no NSServices entry")

for service in services:
    label = service.get("NSMenuItem", {}).get("default", "<unnamed>")
    check(service.get("NSMessage") == "rewriteSelection", f"{label}: unexpected NSMessage")
    check(
        service.get("NSSendTypes") == ["public.utf8-plain-text"],
        f"{label}: unexpected NSSendTypes",
    )
    check(
        service.get("NSReturnTypes") == ["public.utf8-plain-text"],
        f"{label}: unexpected NSReturnTypes",
    )
    check(service.get("NSRestricted") is False, f"{label}: NSRestricted must be false")
    # AppKit treats a Service as hung past roughly 30s, and the provider bails at
    # RewriteTimeouts.service (24s). A larger value here just strands the caller.
    timeout = int(service.get("NSTimeout", "0"))
    check(0 < timeout <= 30_000, f"{label}: NSTimeout must be <= 30000, found {timeout}")
    # NSUserData pins a Service entry to one action; RewriteServiceProvider reads
    # it. Missing means the entry silently inherits the app's last selection.
    check("NSUserData" in service, f"{label}: missing NSUserData")

# Required for distribution; absent it prompts on every upload.
check(
    info.get("ITSAppUsesNonExemptEncryption") is False,
    "ITSAppUsesNonExemptEncryption must be present and false",
)


# --- Privacy manifest --------------------------------------------------------
privacy = load_plist("Pluma/PrivacyInfo.xcprivacy")
check(privacy.get("NSPrivacyTracking") is False, "NSPrivacyTracking must be false")
check(
    privacy.get("NSPrivacyCollectedDataTypes") == [],
    "NSPrivacyCollectedDataTypes must be empty",
)
check(
    not privacy.get("NSPrivacyTrackingDomains"),
    "NSPrivacyTrackingDomains must be empty",
)
check(
    {
        "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
        "NSPrivacyAccessedAPITypeReasons": ["CA92.1"],
    }
    in privacy.get("NSPrivacyAccessedAPITypes", []),
    "Missing the UserDefaults required-reason declaration (CA92.1)",
)


# --- Entitlements ------------------------------------------------------------
# pluma is NOT sandboxed: Accessibility-based cross-app insertion is incompatible
# with the App Sandbox. That is a deliberate product decision (issue #11's
# two-tier distribution), so assert the shape we actually ship.
entitlements = load_plist("Pluma/Pluma.entitlements")
check(
    entitlements.get("com.apple.security.network.client") is True,
    "network.client entitlement is required for Ollama and OpenAI",
)
check(
    "com.apple.security.app-sandbox" not in entitlements,
    "app-sandbox is incompatible with Accessibility insertion; remove it or "
    "update this check alongside a documented architecture change",
)


if FAILURES:
    print("Shipping configuration is INVALID:", file=sys.stderr)
    for failure in FAILURES:
        print(f"  - {failure}", file=sys.stderr)
    sys.exit(1)

print(f"Shipping configuration is valid ({len(services)} Service entry/entries)")
