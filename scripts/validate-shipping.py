#!/usr/bin/env python3

from pathlib import Path
import plistlib


ROOT = Path(__file__).resolve().parent.parent


def load_plist(path: str) -> dict:
    with (ROOT / path).open("rb") as file:
        return plistlib.load(file)


swift_source = "\n".join(
    path.read_text(encoding="utf-8")
    for path in (ROOT / "Rewrite").rglob("*.swift")
)
for forbidden_global_input_api in (
    "import Carbon",
    "RegisterEventHotKey",
    "CGEvent.tapCreate",
    "CGEventTapCreate",
    "addGlobalMonitorForEvents",
):
    assert forbidden_global_input_api not in swift_source, (
        f"Global input API found: {forbidden_global_input_api}"
    )

info = load_plist("Rewrite/Info.plist")
services = info["NSServices"]
assert len(services) == 1
service = services[0]
assert service["NSMessage"] == "rewriteSelection"
assert service["NSTimeout"] == "30000"
assert service["NSSendTypes"] == ["public.utf8-plain-text"]
assert service["NSReturnTypes"] == ["public.utf8-plain-text"]
assert service["NSServiceCategory"] == "public.text"
assert service["NSRestricted"] is False

privacy = load_plist("Rewrite/PrivacyInfo.xcprivacy")
assert privacy["NSPrivacyTracking"] is False
assert privacy["NSPrivacyCollectedDataTypes"] == []
assert {
    "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
    "NSPrivacyAccessedAPITypeReasons": ["CA92.1"],
} in privacy["NSPrivacyAccessedAPITypes"]

entitlements = load_plist("Rewrite/Rewrite.entitlements")
assert entitlements == {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.network.client": True,
}

print("Shipping configuration is valid")
