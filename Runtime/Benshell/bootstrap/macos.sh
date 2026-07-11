#!/usr/bin/env zsh
set -euo pipefail

DRY_RUN=0

say() {
  print -- "$*"
}

die() {
  print -u2 -- "macOS bootstrap: $*"
  exit 1
}

usage() {
  cat <<'EOF'
Usage: bootstrap/macos.sh [command] [options]

Commands:
  apply       Apply light, low-risk macOS preferences (default)
  doctor      Show current status for managed preferences
  help        Show this help

Options:
  --dry-run   Print commands without writing preferences
  -h, --help  Show this help

This script intentionally stays thin. It does not import a full defaults dump,
does not rewrite Dock app icons, and does not touch privacy/admin settings.
EOF
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "this script only supports macOS"
}

run_cmd() {
  if (( DRY_RUN )); then
    say "would run: ${(@q)*}"
    return 0
  fi

  "$@"
}

write_default() {
  local domain="$1"
  local key="$2"
  local type="$3"
  local value="$4"

  run_cmd defaults write "$domain" "$key" "$type" "$value"
}

read_default() {
  local domain="$1"
  local key="$2"
  local value

  value="$(defaults read "$domain" "$key" 2>/dev/null || true)"
  if [[ -n "$value" ]]; then
    say "$domain $key=$value"
  else
    say "$domain $key=<unset>"
  fi
}

restart_if_needed() {
  if (( DRY_RUN )); then
    say "would run: killall Finder SystemUIServer"
    return 0
  fi

  killall Finder >/dev/null 2>&1 || true
  killall SystemUIServer >/dev/null 2>&1 || true
}

run_doctor() {
  require_macos

  say "macOS:"
  sw_vers

  say ""
  say "Managed preferences:"
  read_default NSGlobalDomain AppleShowAllExtensions
  read_default com.apple.finder ShowPathbar
  read_default com.apple.finder ShowStatusBar
  read_default NSGlobalDomain NSNavPanelExpandedStateForSaveMode
  read_default NSGlobalDomain NSNavPanelExpandedStateForSaveMode2
  read_default NSGlobalDomain PMPrintingExpandedStateForPrint
  read_default NSGlobalDomain PMPrintingExpandedStateForPrint2
}

run_apply() {
  require_macos

  say "Applying light macOS preferences"

  write_default NSGlobalDomain AppleShowAllExtensions -bool true
  write_default com.apple.finder ShowPathbar -bool true
  write_default com.apple.finder ShowStatusBar -bool true
  write_default NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
  write_default NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
  write_default NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
  write_default NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

  restart_if_needed
  say "macOS preferences complete"
}

command_name="apply"

while (( $# > 0 )); do
  case "$1" in
    apply|doctor)
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
    *)
      usage
      die "unknown option or command: $1"
      ;;
  esac
done

case "$command_name" in
  apply) run_apply ;;
  doctor) run_doctor ;;
esac
