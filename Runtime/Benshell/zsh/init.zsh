# Benshell runtime layer.

if [[ "${BENSHELL_LOADED_PID:-}" == "$$" ]]; then
  return 0 2>/dev/null || exit 0
fi
typeset -g BENSHELL_LOADED_PID="$$"
unset BENSHELL_LOADED

if [[ -z "${BENSHELL_HOME:-}" ]]; then
  _benshell_source="${(%):-%N}"
  export BENSHELL_HOME="${_benshell_source:A:h:h}"
fi

_benshell_prepend_path() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0

  case ":$PATH:" in
    *":$dir:"*) ;;
    *) export PATH="$dir:$PATH" ;;
  esac
}

_benshell_remove_path() {
  local dir="$1"
  [[ -n "$dir" ]] || return 0

  local -a parts filtered
  local part
  parts=("${(@s/:/)PATH}")
  filtered=()

  for part in $parts; do
    [[ "$part" == "$dir" ]] && continue
    filtered+=("$part")
  done

  export PATH="${(j/:/)filtered}"
}

[[ -f "$BENSHELL_HOME/zsh/exports.zsh" ]] && source "$BENSHELL_HOME/zsh/exports.zsh"

_benshell_remove_path "/Users/ben/Desktop/Benshell/scripts"
_benshell_remove_path "$DEEPTUTOR_HOME/.venv/bin"
_benshell_remove_path "$NANOBOT_HOME/.venv/bin"
_benshell_prepend_path "$BENSHELL_HOME/scripts"
if [[ -n "${BENBENBEN_RUNTIME_HOME:-}" ]]; then
  _benshell_remove_path "$BENBENBEN_RUNTIME_HOME/bin"
  _benshell_prepend_path "$BENBENBEN_RUNTIME_HOME/bin"
fi

for _benshell_file in "$BENSHELL_HOME"/zsh/plugins/*.zsh(N); do
  source "$_benshell_file"
done

for _benshell_file in "$BENSHELL_HOME"/zsh/functions/*.zsh(N); do
  source "$_benshell_file"
done

for _benshell_file in "$BENSHELL_HOME"/zsh/aliases/*.zsh(N); do
  source "$_benshell_file"
done

unset _benshell_file _benshell_source
