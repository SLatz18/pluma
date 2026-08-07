#!/bin/bash
set -euo pipefail

if [[ -n "${DESIGN_SYSTEM_BASE:-}" ]]; then
  base="$DESIGN_SYSTEM_BASE"
elif [[ -n "${GITHUB_BASE_REF:-}" ]] && git rev-parse --verify "origin/$GITHUB_BASE_REF" >/dev/null 2>&1; then
  base="origin/$GITHUB_BASE_REF"
elif [[ "$(git branch --show-current)" != "main" ]] && git rev-parse --verify main >/dev/null 2>&1; then
  base="main"
else
  base="HEAD^"
fi

# Template form works with both BSD (macOS) and GNU (Linux) mktemp; -t does not.
added_lines="$(mktemp "${TMPDIR:-/tmp}/pluma-design-system.XXXXXX")"
trap 'rm -f "$added_lines"' EXIT

git diff --unified=0 "$base" -- Pluma '*.swift' |
  awk '
    /^\+\+\+ b\// { file = substr($0, 7); next }
    /^\+/ && !/^\+\+\+/ {
      if (file !~ /^Pluma\/DesignSystem\// &&
          file != "Pluma/Autocomplete/SuggestionOverlayController.swift" &&
          file != "Pluma/Autocomplete/GhostTextView.swift" &&
          file !~ /^Pluma\/Developer\// &&
          file != "Pluma/Views/DeveloperView.swift") {
        print file ":" substr($0, 2)
      }
    }
  ' > "$added_lines"

if rg -n \
  'RoundedRectangle\(cornerRadius: [0-9]|\.font\(\.system\(size: [0-9]|Color\.(indigo|pink|mint)\b|NSVisualEffectView|struct [A-Za-z0-9_]*(Card|Badge|Pill)' \
  "$added_lines"; then
  echo "New visual primitives must use Pluma/DesignSystem."
  echo "Document a platform-native exception in docs/DESIGN_SYSTEM.md when reuse is not appropriate."
  exit 1
fi

echo "Design-system drift check passed."
