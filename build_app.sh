#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
ACTION="${2:-}"
APP="Accentum.app"
BIN_NAME="Accentum"

echo "▸ swift build ($CONFIG)…"
swift build -c "$CONFIG"
BIN_PATH=".build/$CONFIG/$BIN_NAME"

echo "▸ assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Accentum</string>
    <key>CFBundleDisplayName</key><string>Accentum</string>
    <key>CFBundleIdentifier</key><string>com.accentum.controller</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>Accentum</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Accentum talks to your Sennheiser headphones over Bluetooth to control noise cancellation, transparency, and EQ.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>Accentum talks to your Sennheiser headphones over Bluetooth.</string>
</dict>
</plist>
PLIST

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  echo "▸ codesigning as: $CODESIGN_IDENTITY"
  codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP" >/dev/null 2>&1 \
    && echo "  signed" || codesign --force --deep --sign - "$APP" >/dev/null 2>&1
else
  echo "▸ codesigning (ad-hoc, no keychain prompt)…"
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi

echo "✓ Built $(pwd)/$APP"
echo "  Run: open $APP"
echo "  Or:  ./build_app.sh $CONFIG relaunch"

if [ "$ACTION" = "relaunch" ]; then
  echo "▸ relaunching Accentum…"
  pkill -x "$BIN_NAME" 2>/dev/null || true
  # Avoid Launch Services error -600 (open racing pkill).
  for _ in {1..20}; do
    pgrep -x "$BIN_NAME" >/dev/null || break
    sleep 0.1
  done
  open "$(pwd)/$APP"
fi
