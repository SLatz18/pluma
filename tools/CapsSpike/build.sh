#!/bin/bash
# Builds CapsSpike and wraps it in a .app bundle so macOS can attach a stable
# Accessibility grant to it. Run from tools/CapsSpike/.
set -euo pipefail
cd "$(dirname "$0")"

echo "Building (release)…"
swift build -c release

BIN=".build/release/CapsSpike"
APP="CapsSpike.app"
CONTENTS="$APP/Contents"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/CapsSpike"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>CapsSpike</string>
  <key>CFBundleDisplayName</key><string>CapsSpike</string>
  <key>CFBundleIdentifier</key><string>com.scottlatz.CapsSpike</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>CapsSpike</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "Ad-hoc signing…"
codesign --force --sign - --timestamp=none "$APP"

echo "Built $(pwd)/$APP"
echo "Launch with: open ./$APP"
