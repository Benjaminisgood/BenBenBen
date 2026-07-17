#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_PATH="${0:A}"
SCRIPT_DIR="${SCRIPT_PATH:h}"
BENSHELL_HOME="${BENSHELL_HOME:-${SCRIPT_DIR:h}}"
BREWFILE="${BENSHELL_BREWFILE:-$BENSHELL_HOME/Brewfile}"

DRY_RUN=0
NO_CASK=0

say() {
  print -- "$*"
}

die() {
  print -u2 -- "brew bootstrap: $*"
  exit 1
}

usage() {
  cat <<'EOF'
Usage: bootstrap/brew.sh [command] [options]

Commands:
  bundle      Install or update packages from Brewfile (default)
  doctor      Check Homebrew and Brewfile readiness
  help        Show this help

Options:
  --dry-run   Print the brew bundle command without installing
  --no-cask   Install/check formulae only; skip Homebrew Cask entries
  -h, --help  Show this help

Environment:
  BENSHELL_HOME      Defaults to the repository root
  BENSHELL_BREWFILE  Defaults to $BENSHELL_HOME/Brewfile
EOF
}

resolve_brew() {
  if command -v brew >/dev/null 2>&1; then
    command -v brew
    return 0
  fi

  if [[ -x /opt/homebrew/bin/brew ]]; then
    print -- /opt/homebrew/bin/brew
    return 0
  fi

  if [[ -x /usr/local/bin/brew ]]; then
    print -- /usr/local/bin/brew
    return 0
  fi

  return 1
}

require_brew() {
  BREW_BIN="$(resolve_brew 2>/dev/null || true)"
  [[ -n "${BREW_BIN:-}" ]] || die "Homebrew not found. Install it with:
  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
}

require_brewfile() {
  [[ -f "$BREWFILE" ]] || die "Brewfile not found: $BREWFILE"
}

cask_skip_value() {
  local -a casks
  casks=("${(@f)$(HOMEBREW_NO_AUTO_UPDATE=1 "$BREW_BIN" bundle list --file "$BREWFILE" --cask 2>/dev/null || true)}")
  print -r -- "${(j: :)casks}"
}

run_brew_bundle_check() {
  local cask_skip=""

  if (( NO_CASK )); then
    cask_skip="$(cask_skip_value)"
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_BUNDLE_CASK_SKIP="$cask_skip" "$BREW_BIN" bundle check --no-upgrade --file "$BREWFILE"
  else
    HOMEBREW_NO_AUTO_UPDATE=1 "$BREW_BIN" bundle check --no-upgrade --file "$BREWFILE"
  fi
}

run_doctor() {
  require_brew

  say "Homebrew: $BREW_BIN"
  "$BREW_BIN" --version | sed -n '1,2p'

  require_brewfile
  say "Brewfile: $BREWFILE"

  local formula_count cask_count
  formula_count="$(grep -Ec '^[[:space:]]*brew[[:space:]]+"' "$BREWFILE" || true)"
  cask_count="$(grep -Ec '^[[:space:]]*cask[[:space:]]+"' "$BREWFILE" || true)"
  say "Formulae: $formula_count"
  if (( NO_CASK )); then
    say "Casks: skipped by --no-cask"
  else
    say "Casks: $cask_count"
  fi

  say ""
  set +e
  run_brew_bundle_check
  local check_status=$?
  set -e

  if (( check_status == 0 )); then
    say "Brewfile dependencies: installed"
  else
    say "Brewfile dependencies: missing or outdated items listed above"
  fi
}

run_bundle() {
  require_brew
  require_brewfile

  local -a args
  args=(bundle --file "$BREWFILE")
  local cask_skip=""
  (( NO_CASK )) && cask_skip="$(cask_skip_value)"

  if (( DRY_RUN )); then
    if (( NO_CASK )); then
      say "would set: HOMEBREW_BUNDLE_CASK_SKIP=${(qq)cask_skip}"
      say "would run: ${(q)BREW_BIN} ${(@q)args}"
    else
      say "would run: ${(q)BREW_BIN} ${(@q)args}"
    fi
    return 0
  fi

  if (( NO_CASK )); then
    HOMEBREW_BUNDLE_CASK_SKIP="$cask_skip" "$BREW_BIN" "${args[@]}"
  else
    "$BREW_BIN" "${args[@]}"
  fi
}

command_name="bundle"

while (( $# > 0 )); do
  case "$1" in
    bundle|doctor)
      command_name="$1"
      shift
      ;;
    help|-h|--help)
      usage
      exit 0
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --no-cask)
      NO_CASK=1
      shift
      ;;
    *)
      usage
      die "unknown option or command: $1"
      ;;
  esac
done

case "$command_name" in
  bundle) run_bundle ;;
  doctor) run_doctor ;;
esac
