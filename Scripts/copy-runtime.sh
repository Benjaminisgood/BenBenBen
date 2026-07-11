#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${RUNTIME_SOURCE_DIR:-$ROOT_DIR/Runtime}"
DESTINATION="${1:-}"

if [[ -z "$DESTINATION" ]]; then
  echo "usage: $0 DESTINATION" >&2
  exit 2
fi

for required in VERSION manifest.json bin/benbenben install.zsh Benshell/zsh/init.zsh; do
  if [[ ! -f "$SOURCE_DIR/$required" ]]; then
    echo "Runtime resource is missing: $SOURCE_DIR/$required" >&2
    exit 1
  fi
done

rm -rf "$DESTINATION"
mkdir -p "$DESTINATION"
if [[ -x /usr/bin/ditto ]]; then
  /usr/bin/ditto "$SOURCE_DIR" "$DESTINATION"
else
  cp -R "$SOURCE_DIR/." "$DESTINATION/"
fi
rm -rf "$DESTINATION/bin/__pycache__"
chmod +x \
  "$DESTINATION/install.zsh" \
  "$DESTINATION/bin/benbenben" \
  "$DESTINATION/bin/benbenben-mcp" \
  "$DESTINATION/bin/bbb" \
  "$DESTINATION/bin/benshell" \
  "$DESTINATION/bin/notchwow" \
  "$DESTINATION/bin/nw" \
  "$DESTINATION/Benshell/scripts/"* \
  "$DESTINATION/Benshell/bootstrap/"*.sh

/usr/bin/python3 - "$DESTINATION" <<'PY'
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
version = (root / "VERSION").read_text(encoding="utf-8").strip()
manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
if manifest.get("schemaVersion") != 1 or manifest.get("runtimeVersion") != version:
    raise SystemExit("invalid bundled Runtime manifest")
helper = manifest.get("mcpHelper")
if helper != "bin/benbenben-mcp" or not (root / helper).is_file():
    raise SystemExit("invalid bundled MCP helper")
PY
