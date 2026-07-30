#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}

cd "$PROJECT_DIR"

# Pluma.xcodeproj is generated AND committed, so a different XcodeGen version
# would silently rewrite the pbxproj and show up as unrelated diff noise in
# every PR. Pin the generator so the committed project stays reproducible.
EXPECTED_XCODEGEN_VERSION="2.46.0"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen is required. Install it with: brew install xcodegen" >&2
    exit 1
fi

ACTUAL_XCODEGEN_VERSION="${$(xcodegen --version)##Version: }"
if [[ "$ACTUAL_XCODEGEN_VERSION" != "$EXPECTED_XCODEGEN_VERSION" ]]; then
    echo "Expected XcodeGen $EXPECTED_XCODEGEN_VERSION, found $ACTUAL_XCODEGEN_VERSION." >&2
    echo "Install the pinned version, or update EXPECTED_XCODEGEN_VERSION here and" >&2
    echo "commit the regenerated project in the same change." >&2
    exit 1
fi

swift scripts/generate-icon.swift
xcodegen generate --spec project.yml

echo "Generated Pluma.xcodeproj with XcodeGen $ACTUAL_XCODEGEN_VERSION"
