#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="notchwow"
BUNDLE_ID="io.github.benjaminisgood.notchwow.dev"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
SOURCE_ICON="$ROOT_DIR/Resources/AppIcon.png"

cd "$ROOT_DIR"

stop_app() {
  local name="$1"
  local pid

  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    pkill -TERM -P "$pid" >/dev/null 2>&1 || true
    kill -TERM "$pid" >/dev/null 2>&1 || true
  done < <(pgrep -x "$name" || true)
}

stop_app "$APP_NAME"
sleep 0.3
stop_app "$APP_NAME"

swift build --product "$APP_NAME"
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

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
  iconutil -c icns "$ICONSET_DIR" -o "$APP_RESOURCES/AppIcon.icns"
  rm -rf "$TMP_DIR"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>notchwow uses Terminal automation to focus tabs, read terminal contents, and send commands you choose to run.</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
