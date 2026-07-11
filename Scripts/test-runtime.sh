#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export HOME="$TMP_DIR/home"
mkdir -p "$HOME"
cat > "$HOME/.zshrc" <<'EOF'
export KEEP_ME="yes"
export BENSHELL_HOME="/Users/ben/Desktop/Benshell"
[[ -f "$BENSHELL_HOME/zsh/init.zsh" ]] && source "$BENSHELL_HOME/zsh/init.zsh"
EOF

APP_SUPPORT_HOME="$HOME/Library/Application Support/BenBenBen"
CURRENT="$APP_SUPPORT_HOME/Runtime/current"
RUNTIME_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/Runtime/VERSION")"

"$ROOT_DIR/Runtime/install.zsh" doctor --source "$ROOT_DIR/Runtime" >/dev/null
"$ROOT_DIR/Scripts/install-runtime.sh" install \
  --home "$APP_SUPPORT_HOME" \
  --zshrc "$HOME/.zshrc" >/dev/null

[[ -L "$CURRENT" ]]
[[ "$(readlink "$CURRENT")" == "releases/$RUNTIME_VERSION" ]]
[[ -x "$CURRENT/bin/benbenben" ]]
[[ -x "$CURRENT/bin/benbenben-mcp" ]]
[[ -x "$CURRENT/Benshell/scripts/benbenben-app" ]]
[[ -f "$CURRENT/Benshell/Brewfile" ]]
[[ -f "$CURRENT/Benshell/bootstrap/install.sh" ]]
[[ -f "$CURRENT/Benshell/zsh/aliases/ai.zsh" ]]

BACKUPS_BEFORE="$(find "$HOME" -maxdepth 1 -name '.zshrc.benbenben-backup.*' | wc -l | tr -d ' ')"
"$ROOT_DIR/Scripts/install-runtime.sh" install \
  --home "$APP_SUPPORT_HOME" \
  --zshrc "$HOME/.zshrc" >/dev/null
BACKUPS_AFTER="$(find "$HOME" -maxdepth 1 -name '.zshrc.benbenben-backup.*' | wc -l | tr -d ' ')"
[[ "$BACKUPS_BEFORE" == "1" ]]
[[ "$BACKUPS_AFTER" == "$BACKUPS_BEFORE" ]]
[[ "$(grep -c '^# >>> BenBenBen Runtime >>>$' "$HOME/.zshrc")" == "1" ]]
! grep -q '/Users/ben/Desktop/Benshell' "$HOME/.zshrc"
grep -q 'export KEEP_ME="yes"' "$HOME/.zshrc"

"$CURRENT/bin/benbenben" runtime status --json > "$TMP_DIR/runtime-status.json"
"$CURRENT/bin/benbenben" tools list --json > "$TMP_DIR/tools-list.json"
"$CURRENT/bin/benbenben" tools status runtime.version --json > "$TMP_DIR/tool-status.json"
"$CURRENT/bin/benbenben" tools run runtime.version --json > "$TMP_DIR/tool-run.json"

set +e
"$CURRENT/bin/benbenben" tools run benbenben.build --json > "$TMP_DIR/approval.json"
APPROVAL_STATUS=$?
set -e
[[ "$APPROVAL_STATUS" == "3" ]]
"$CURRENT/bin/benbenben" tools run benbenben.build --yes --dry-run --json > "$TMP_DIR/build-dry-run.json"

cat > "$TMP_DIR/mcp-input.jsonl" <<EOF
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_workflows","arguments":{}}}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"run_workflow","arguments":{"id":"benbenben.build"}}}
EOF
"$CURRENT/bin/benbenben-mcp" < "$TMP_DIR/mcp-input.jsonl" > "$TMP_DIR/mcp-output.jsonl"

/usr/bin/python3 - "$TMP_DIR" "$RUNTIME_VERSION" <<'PY'
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
expected_version = sys.argv[2]
runtime = json.loads((root / "runtime-status.json").read_text())
tools = json.loads((root / "tools-list.json").read_text())
status = json.loads((root / "tool-status.json").read_text())
run = json.loads((root / "tool-run.json").read_text())
approval = json.loads((root / "approval.json").read_text())
dry_run = json.loads((root / "build-dry-run.json").read_text())
mcp = [json.loads(line) for line in (root / "mcp-output.jsonl").read_text().splitlines()]

assert runtime["runtimeVersion"] == expected_version
assert runtime["ready"] is True
assert tools["schemaVersion"] == 1
assert any(item["id"] == "benbenben.status" for item in tools["tools"])
assert status["available"] is True
assert run["status"] == "success" and run["stdout"].strip() == expected_version
assert approval["status"] == "approvalRequired" and approval["exitCode"] == 3
assert dry_run["status"] == "dryRun"
assert mcp[0]["result"]["serverInfo"]["name"] == "benbenben-mcp"
tool_names = {item["name"] for item in mcp[1]["result"]["tools"]}
assert {"search_knowledge", "read_document", "recent_activity", "run_workflow", "run_job"} <= tool_names
assert mcp[2]["result"]["structuredContent"]["count"] > 0
assert mcp[3]["result"]["structuredContent"]["status"] == "approval_required"
PY

ZDOTDIR="$HOME" /bin/zsh -f -c 'source "$ZDOTDIR/.zshrc"; [[ "$(command -v benbenben)" == "$BENBENBEN_RUNTIME_HOME/bin/benbenben" ]]'

BUNDLED="$TMP_DIR/BundledRuntime"
"$ROOT_DIR/Scripts/copy-runtime.sh" "$BUNDLED"
[[ -x "$BUNDLED/bin/benbenben" ]]
[[ -x "$BUNDLED/bin/benbenben-mcp" ]]
[[ -f "$BUNDLED/Benshell/AGENTS.md" ]]

echo "Runtime tests passed"
