vsc() {
  local code_cmd
  if [[ -x /Applications/Visual\ Studio\ Code.app/Contents/Resources/app/bin/code ]]; then
    code_cmd=/Applications/Visual\ Studio\ Code.app/Contents/Resources/app/bin/code
  else
    code_cmd=code
  fi
  "$code_cmd" "${1:-.}"
}
