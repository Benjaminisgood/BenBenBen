#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_PATH="${0:A}"
DEFAULT_SOURCE="${SCRIPT_PATH:h}"
SOURCE_ROOT="${BENBENBEN_RUNTIME_SOURCE:-$DEFAULT_SOURCE}"
APP_SUPPORT_HOME="${BENBENBEN_APP_SUPPORT_HOME:-$HOME/Library/Application Support/BenBenBen}"
ZSHRC_PATH="${BENBENBEN_ZSHRC_PATH:-$HOME/.zshrc}"
UPDATE_ZSHRC=1
DRY_RUN=0
COMMAND="install"
START_MARKER="# >>> BenBenBen Runtime >>>"
END_MARKER="# <<< BenBenBen Runtime <<<"

say() {
  print -- "$*"
}

die() {
  print -u2 -- "BenBenBen Runtime installer: $*"
  exit 1
}

usage() {
  cat <<'EOF'
Usage: install.zsh [install|status|doctor] [options]

Commands:
  install       Atomically install Runtime and update the managed .zshrc block
  status        Show the current Runtime link and installed version
  doctor        Validate the source Runtime without changing the machine

Options:
  --source PATH   Runtime source containing VERSION, manifest.json, bin, Benshell
  --home PATH     App support root (default: ~/Library/Application Support/BenBenBen)
  --zshrc PATH    zsh startup file (default: ~/.zshrc)
  --no-zshrc      Install Runtime without editing a shell startup file
  --dry-run       Print the install destination without writing anything
  -h, --help      Show this help

This installer never runs Brewfile, macOS defaults, Git sync/pull/push, or service startup.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    install|status|doctor)
      COMMAND="$1"
      shift
      ;;
    --source)
      (( $# >= 2 )) || die "--source requires a path"
      SOURCE_ROOT="$2"
      shift 2
      ;;
    --home)
      (( $# >= 2 )) || die "--home requires a path"
      APP_SUPPORT_HOME="$2"
      shift 2
      ;;
    --zshrc)
      (( $# >= 2 )) || die "--zshrc requires a path"
      ZSHRC_PATH="$2"
      shift 2
      ;;
    --no-zshrc)
      UPDATE_ZSHRC=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    help|-h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      die "unknown command or option: $1"
      ;;
  esac
done

SOURCE_ROOT="${SOURCE_ROOT:A}"
APP_SUPPORT_HOME="${APP_SUPPORT_HOME:A}"
ZSHRC_PATH="${ZSHRC_PATH:A}"
RUNTIME_HOME="$APP_SUPPORT_HOME/Runtime"
RELEASES_HOME="$RUNTIME_HOME/releases"
CURRENT_LINK="$RUNTIME_HOME/current"

validate_source() {
  [[ -d "$SOURCE_ROOT" ]] || die "Runtime source does not exist: $SOURCE_ROOT"
  [[ -f "$SOURCE_ROOT/VERSION" ]] || die "VERSION is missing from $SOURCE_ROOT"
  [[ -f "$SOURCE_ROOT/manifest.json" ]] || die "manifest.json is missing from $SOURCE_ROOT"
  [[ -f "$SOURCE_ROOT/bin/benbenben" ]] || die "bin/benbenben is missing from $SOURCE_ROOT"
  [[ -f "$SOURCE_ROOT/Benshell/zsh/init.zsh" ]] || die "Benshell/zsh/init.zsh is missing from $SOURCE_ROOT"

  VERSION="$(<"$SOURCE_ROOT/VERSION")"
  VERSION="${VERSION//[[:space:]]/}"
  [[ -n "$VERSION" ]] || die "VERSION is empty"
  print -r -- "$VERSION" | /usr/bin/grep -Eq '^[A-Za-z0-9._-]+$' || die "VERSION contains unsafe characters: $VERSION"

  /usr/bin/python3 - "$SOURCE_ROOT" "$VERSION" <<'PY'
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
version = sys.argv[2]
manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
if manifest.get("schemaVersion") != 1:
    raise SystemExit("manifest schemaVersion must be 1")
if manifest.get("runtimeVersion") != version:
    raise SystemExit("manifest runtimeVersion does not match VERSION")
if not isinstance(manifest.get("actions"), list):
    raise SystemExit("manifest actions must be an array")
PY
}

copy_runtime() {
  local destination="$1"
  if [[ -x /usr/bin/ditto ]]; then
    /usr/bin/ditto "$SOURCE_ROOT" "$destination"
  else
    /bin/cp -R "$SOURCE_ROOT/." "$destination/"
  fi
}

install_release() {
  local release_home="$RELEASES_HOME/$VERSION"
  local staging_home="$RELEASES_HOME/.${VERSION}.staging.$$"
  local next_link="$RUNTIME_HOME/.current.$$"

  if (( DRY_RUN )); then
    say "Would install: $SOURCE_ROOT"
    say "Release: $release_home"
    say "Current: $CURRENT_LINK -> releases/$VERSION"
    (( UPDATE_ZSHRC )) && say "Would manage: $ZSHRC_PATH"
    return 0
  fi

  /bin/mkdir -p "$RELEASES_HOME"
  if [[ ! -d "$release_home" ]]; then
    /bin/rm -rf "$staging_home"
    /bin/mkdir -p "$staging_home"
    trap '/bin/rm -rf -- "$staging_home" "$next_link"' EXIT INT TERM
    copy_runtime "$staging_home"
    /bin/chmod +x \
      "$staging_home/install.zsh" \
      "$staging_home/bin/benbenben" \
      "$staging_home/bin/benbenben-mcp" \
      "$staging_home/bin/bbb" \
      "$staging_home/Benshell/scripts/"* \
      "$staging_home/Benshell/bootstrap/"*.sh
    /bin/mv "$staging_home" "$release_home"
  else
    [[ "$(<"$release_home/VERSION")" == "$VERSION" ]] || die "existing release is invalid: $release_home"
  fi

  /bin/ln -s "releases/$VERSION" "$next_link"
  [[ ! -e "$CURRENT_LINK" || -L "$CURRENT_LINK" ]] \
    || die "current Runtime path must be a symbolic link: $CURRENT_LINK"
  /bin/mv -f "$next_link" "$CURRENT_LINK"
  trap - EXIT INT TERM
  say "Installed BenBenBen Runtime $VERSION"
  say "Current: $CURRENT_LINK"
}

update_zshrc() {
  (( UPDATE_ZSHRC )) || return 0
  (( DRY_RUN )) && return 0

  local zshrc_dir="${ZSHRC_PATH:h}"
  local temporary
  local backup
  local source_path="/dev/null"

  /bin/mkdir -p "$zshrc_dir"
  [[ -f "$ZSHRC_PATH" ]] && source_path="$ZSHRC_PATH"
  temporary="$(/usr/bin/mktemp "$zshrc_dir/.zshrc.benbenben.XXXXXX")"

  /usr/bin/python3 - "$source_path" "$temporary" "$START_MARKER" "$END_MARKER" "$CURRENT_LINK" "$HOME" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
start, end = sys.argv[3], sys.argv[4]
current_link = sys.argv[5]
home = sys.argv[6].rstrip("/")
if current_link.startswith(home + "/"):
    runtime_default = "$HOME/" + current_link[len(home) + 1:]
else:
    runtime_default = current_link.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("`", "\\`")
lines = source.read_text(encoding="utf-8").splitlines() if source != Path("/dev/null") else []
kept = []
managed = False
for line in lines:
    if line == start:
        managed = True
        continue
    if line == end:
        managed = False
        continue
    if managed:
        continue
    kept.append(line)

while kept and not kept[-1].strip():
    kept.pop()
if kept:
    kept.append("")
kept.extend([
    "# >>> BenBenBen Runtime >>>",
    'export BENBENBEN_RUNTIME_HOME="${BENBENBEN_RUNTIME_HOME:-' + runtime_default + '}"',
    'export BENSHELL_HOME="$BENBENBEN_RUNTIME_HOME/Benshell"',
    'case ":$PATH:" in',
    '  *":$BENBENBEN_RUNTIME_HOME/bin:"*) ;;',
    '  *) export PATH="$BENBENBEN_RUNTIME_HOME/bin:$PATH" ;;',
    'esac',
    '[[ -r "$BENSHELL_HOME/zsh/init.zsh" ]] && source "$BENSHELL_HOME/zsh/init.zsh"',
    "# <<< BenBenBen Runtime <<<",
])
destination.write_text("\n".join(kept) + "\n", encoding="utf-8")
PY

  if [[ -f "$ZSHRC_PATH" ]] && /usr/bin/cmp -s "$ZSHRC_PATH" "$temporary"; then
    /bin/rm -f "$temporary"
    say ".zshrc already up to date"
    return 0
  fi

  if [[ -f "$ZSHRC_PATH" ]]; then
    backup="$ZSHRC_PATH.benbenben-backup.$(/bin/date +%Y%m%d-%H%M%S)"
    [[ ! -e "$backup" ]] || backup="$backup.$$"
    /bin/cp -p "$ZSHRC_PATH" "$backup"
    say "Backed up shell config: $backup"
  fi
  /bin/chmod 600 "$temporary"
  /bin/mv -f "$temporary" "$ZSHRC_PATH"
  say "Updated shell config: $ZSHRC_PATH"
}

show_status() {
  if [[ ! -L "$CURRENT_LINK" ]]; then
    say "BenBenBen Runtime is not installed at $CURRENT_LINK"
    return 1
  fi
  local target="$(/bin/readlink "$CURRENT_LINK")"
  local installed_version="unknown"
  [[ -f "$CURRENT_LINK/VERSION" ]] && installed_version="$(<"$CURRENT_LINK/VERSION")"
  say "BenBenBen Runtime $installed_version"
  say "current: $CURRENT_LINK -> $target"
}

case "$COMMAND" in
  doctor)
    validate_source
    say "Runtime source is valid: $SOURCE_ROOT"
    say "Version: $VERSION"
    say "No machine state was changed."
    ;;
  status)
    show_status
    ;;
  install)
    validate_source
    install_release
    update_zshrc
    ;;
esac
