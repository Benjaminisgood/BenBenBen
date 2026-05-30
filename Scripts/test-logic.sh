#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

xcrun swiftc \
  -parse-as-library \
  "$ROOT_DIR/Sources/notchwow/AppDefaults.swift" \
  "$ROOT_DIR/Sources/notchwow/WorkspacePaths.swift" \
  "$ROOT_DIR/Sources/notchwow/ShellEscaping.swift" \
  "$ROOT_DIR/Sources/notchwow/TerminalAppBridge.swift" \
  "$ROOT_DIR/Sources/notchwow/TerminalTaskStore.swift" \
  "$ROOT_DIR/Sources/notchwow/LaunchdJobStore.swift" \
  "$ROOT_DIR/Tests/LogicSmokeTests/main.swift" \
  -o "$TMP_DIR/notchwow-logic-tests"

"$TMP_DIR/notchwow-logic-tests"
