#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

xcrun swiftc \
  -parse-as-library \
  "$ROOT_DIR/Sources/BenBenBen/AppDefaults.swift" \
  "$ROOT_DIR/Sources/BenBenBen/WorkspacePaths.swift" \
  "$ROOT_DIR/Sources/BenBenBen/ShellEscaping.swift" \
  "$ROOT_DIR/Sources/BenBenBen/FilePermissionLockStore.swift" \
  "$ROOT_DIR/Sources/BenBenBen/LaunchdJobStore.swift" \
  "$ROOT_DIR/Tests/LogicSmokeTests/main.swift" \
  -o "$TMP_DIR/benbenben-logic-tests"

"$TMP_DIR/benbenben-logic-tests"

MARKDOWN_ENGINE_SOURCES=()
while IFS= read -r source_file; do
  MARKDOWN_ENGINE_SOURCES+=("$source_file")
done < <(find "$ROOT_DIR/Vendor/swift-markdown-engine/Sources/MarkdownEngine" -name '*.swift' | sort)

xcrun swiftc \
  -parse-as-library \
  "${MARKDOWN_ENGINE_SOURCES[@]}" \
  "$ROOT_DIR/Tests/MarkdownEngineSmokeTests/main.swift" \
  -o "$TMP_DIR/markdown-engine-smoke-tests"

"$TMP_DIR/markdown-engine-smoke-tests"

"$ROOT_DIR/Scripts/test-runtime.sh"
