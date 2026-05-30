#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

xcrun swiftc \
  -parse-as-library \
  "$ROOT_DIR/Sources/NotchNotes/WorkspacePaths.swift" \
  "$ROOT_DIR/Sources/NotchNotes/ShellEscaping.swift" \
  "$ROOT_DIR/Sources/NotchNotes/TerminalAppBridge.swift" \
  "$ROOT_DIR/Sources/NotchNotes/TerminalTaskStore.swift" \
  "$ROOT_DIR/Sources/NotchNotes/LaunchdJobStore.swift" \
  "$ROOT_DIR/Tests/LogicSmokeTests/main.swift" \
  -o "$TMP_DIR/notchwow-logic-tests"

"$TMP_DIR/notchwow-logic-tests"
