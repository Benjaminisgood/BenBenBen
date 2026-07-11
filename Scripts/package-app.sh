#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="BenBenBen"
APP_DIR="${APP_DIR:-$ROOT_DIR/dist/$APP_NAME.app}"
APPLICATIONS_APP_DIR="${APPLICATIONS_APP_DIR:-/Applications/$APP_NAME.app}"
COPY_TO_APPLICATIONS="${COPY_TO_APPLICATIONS:-1}"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SOURCE_ICON="$ROOT_DIR/Resources/AppIcon.png"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
RUNTIME_RESOURCES="$RESOURCES_DIR/Runtime"

cd "$ROOT_DIR"
swift build -c release --product "$APP_NAME"
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_BINARY" "$MACOS_DIR/$APP_NAME"
"$ROOT_DIR/Scripts/copy-runtime.sh" "$RUNTIME_RESOURCES"
if [[ -d "$ROOT_DIR/Resources/Mascot" ]]; then
  /usr/bin/ditto "$ROOT_DIR/Resources/Mascot" "$RESOURCES_DIR/Mascot"
fi
CONFIGURATION=release SIGN_IDENTITY="$SIGN_IDENTITY" "$ROOT_DIR/Scripts/embed-login-helper.sh" "$APP_DIR"

if [[ -f "$SOURCE_ICON" ]]; then
  TMP_DIR="$(mktemp -d)"
  ICONSET_DIR="$TMP_DIR/AppIcon.iconset"
  mkdir -p "$ICONSET_DIR"

  sips -z 16 16 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
  rm -rf "$TMP_DIR"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>io.github.benjaminisgood.benbenben</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.1</string>
  <key>CFBundleVersion</key>
  <string>2</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>BenBenBen can open directories you choose in Terminal.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>BenBenBen uses the microphone only while you hold to talk with Ben龙.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>BenBenBen converts your push-to-talk audio into text for your agent.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "Built $APP_DIR"
if [[ "$COPY_TO_APPLICATIONS" == "1" ]]; then
  rm -rf "$APPLICATIONS_APP_DIR"
  cp -R "$APP_DIR" "$APPLICATIONS_APP_DIR"
  echo "Copied $APPLICATIONS_APP_DIR"
fi
