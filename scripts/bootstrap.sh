#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}

cd "$PROJECT_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen is required. Install it with: brew install xcodegen" >&2
    exit 1
fi

EXPECTED_XCODEGEN_VERSION="Version: 2.46.0"
ACTUAL_XCODEGEN_VERSION=$(xcodegen --version)
if [[ "$ACTUAL_XCODEGEN_VERSION" != "$EXPECTED_XCODEGEN_VERSION" ]]; then
    echo "Expected XcodeGen 2.46.0, found: $ACTUAL_XCODEGEN_VERSION" >&2
    exit 1
fi

swift scripts/generate-icon.swift
xcodegen generate --spec project.yml

echo "Generated Rewrite.xcodeproj"
