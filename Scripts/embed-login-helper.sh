#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-}"
CONFIGURATION="${CONFIGURATION:-debug}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
HELPER_NAME="BenBenBenLoginHelper"
HELPER_ID="io.github.benjaminisgood.benbenben.login-helper"

if [[ -z "$APP_BUNDLE" ]]; then
  echo "usage: $0 /path/to/BenBenBen.app" >&2
  exit 2
fi

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION" --product "$HELPER_NAME"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
HELPER_APP="$APP_BUNDLE/Contents/Library/LoginItems/$HELPER_NAME.app"
HELPER_CONTENTS="$HELPER_APP/Contents"
HELPER_MACOS="$HELPER_CONTENTS/MacOS"

rm -rf "$HELPER_APP"
mkdir -p "$HELPER_MACOS"
cp "$BIN_DIR/$HELPER_NAME" "$HELPER_MACOS/$HELPER_NAME"
chmod +x "$HELPER_MACOS/$HELPER_NAME"

cat > "$HELPER_CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$HELPER_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$HELPER_ID</string>
  <key>CFBundleName</key>
  <string>BenBenBen Login Helper</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.1</string>
  <key>CFBundleVersion</key>
  <string>2</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

plutil -lint "$HELPER_CONTENTS/Info.plist" >/dev/null
codesign --force --sign "$SIGN_IDENTITY" "$HELPER_APP"
