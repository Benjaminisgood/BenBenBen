#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_PATH="${0:A}"
SCRIPT_DIR="${SCRIPT_PATH:h}"
BENSHELL_HOME="${BENSHELL_HOME:-${SCRIPT_DIR:h}}"

DRY_RUN=0
SKIP_BREW=0
SKIP_MACOS=0
NO_CASK=0

say() {
  print -- "$*"
}

die() {
  print -u2 -- "install bootstrap: $*"
  exit 1
}

usage() {
  cat <<'EOF'
Usage: bootstrap/install.sh [command] [options]

Commands:
  install       Run the Benshell bootstrap flow (default)
  doctor        Check machine readiness without installing
  help          Show this help

Options:
  --dry-run     Print actions without installing packages or writing defaults
  --skip-brew   Skip Homebrew/Brewfile setup
  --skip-macos  Skip macOS preference setup
  --no-cask     Skip Homebrew Cask entries
  -h, --help    Show this help

Environment:
  BENSHELL_HOME  Defaults to the repository root
EOF
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "this bootstrap currently supports macOS only"
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

check_xcode_clt() {
  local developer_dir
  developer_dir="$(xcode-select -p 2>/dev/null || true)"
  [[ -n "$developer_dir" && -d "$developer_dir" ]]
}

require_xcode_clt() {
  check_xcode_clt || die "Xcode Command Line Tools not found. Install them with:
  xcode-select --install"
}

require_homebrew() {
  BREW_BIN="$(resolve_brew 2>/dev/null || true)"
  [[ -n "${BREW_BIN:-}" ]] || die "Homebrew not found. Install it with:
  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
}

script_path() {
  local name="$1"
  print -- "$BENSHELL_HOME/bootstrap/$name"
}

run_script() {
  local name="$1"
  shift

  local script
  script="$(script_path "$name")"
  [[ -x "$script" ]] || die "$script is missing or not executable"

  "$script" "$@"
}

run_doctor() {
  require_macos

  say "Benshell: $BENSHELL_HOME"
  [[ -d "$BENSHELL_HOME" ]] || die "BENSHELL_HOME does not exist: $BENSHELL_HOME"

  say ""
  say "macOS:"
  sw_vers

  say ""
  if check_xcode_clt; then
    say "Xcode Command Line Tools: $(xcode-select -p)"
  else
    say "Xcode Command Line Tools: missing"
    say "Install with: xcode-select --install"
  fi

  say ""
  if BREW_BIN="$(resolve_brew 2>/dev/null || true)" && [[ -n "$BREW_BIN" ]]; then
    say "Homebrew: $BREW_BIN"
    "$BREW_BIN" --version | sed -n '1,2p'
  else
    say "Homebrew: missing"
    say 'Install with: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  fi

  say ""
  if [[ -f "$BENSHELL_HOME/Brewfile" ]]; then
    say "Brewfile: $BENSHELL_HOME/Brewfile"
  else
    say "Brewfile: missing"
  fi

  if (( ! SKIP_BREW )) && [[ -x "$(script_path brew.sh)" ]]; then
    say ""
    local -a brew_args
    brew_args=(doctor)
    (( NO_CASK )) && brew_args+=(--no-cask)
    run_script brew.sh "${brew_args[@]}" || true
  fi

  if (( ! SKIP_MACOS )) && [[ -x "$(script_path macos.sh)" ]]; then
    say ""
    run_script macos.sh doctor || true
  fi
}

run_install() {
  require_macos
  require_xcode_clt

  say "Benshell: $BENSHELL_HOME"

  if (( SKIP_BREW )); then
    say "Skipping Homebrew bootstrap"
  else
    require_homebrew
    local -a brew_args
    brew_args=(bundle)
    (( DRY_RUN )) && brew_args+=(--dry-run)
    (( NO_CASK )) && brew_args+=(--no-cask)
    run_script brew.sh "${brew_args[@]}"
  fi

  if (( SKIP_MACOS )); then
    say "Skipping macOS preferences"
  else
    local -a macos_args
    macos_args=(apply)
    (( DRY_RUN )) && macos_args+=(--dry-run)
    run_script macos.sh "${macos_args[@]}"
  fi

  say ""
  say "Benshell shell integration:"
  say "  source $BENSHELL_HOME/zsh/init.zsh"
  say ""
  say "Add that line to ~/.zshrc when you want every new shell to load Benshell."
}

command_name="install"

while (( $# > 0 )); do
  case "$1" in
    install|doctor)
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
    --skip-brew)
      SKIP_BREW=1
      shift
      ;;
    --skip-macos)
      SKIP_MACOS=1
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
  install) run_install ;;
  doctor) run_doctor ;;
esac
