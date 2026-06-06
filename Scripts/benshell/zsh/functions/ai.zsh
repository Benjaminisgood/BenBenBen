# nanobot helpers.

nbhome() {
  cd "${NANOBOT_HOME:-/Users/ben/Desktop/nanobot}"
}

nbagent() {
  local home="${NANOBOT_HOME:-/Users/ben/Desktop/nanobot}"
  local bin="$home/.venv/bin/nanobot"

  [[ -x "$bin" ]] || {
    print -u2 "nbagent: $bin not found. Run: nanobot setup"
    return 1
  }

  (cd "$home" && "$bin" agent "$@")
}

nbgateway() {
  local home="${NANOBOT_HOME:-/Users/ben/Desktop/nanobot}"
  local bin="$home/.venv/bin/nanobot"

  [[ -x "$bin" ]] || {
    print -u2 "nbgateway: $bin not found. Run: nanobot setup"
    return 1
  }

  (cd "$home" && "$bin" gateway "$@")
}

nbserve() {
  local home="${NANOBOT_HOME:-/Users/ben/Desktop/nanobot}"
  local bin="$home/.venv/bin/nanobot"
  local port="${NANOBOT_OPENAI_API_PORT:-1234}"
  local host="${NANOBOT_OPENAI_API_HOST:-127.0.0.1}"

  [[ -x "$bin" ]] || {
    print -u2 "nbserve: $bin not found. Run: nanobot setup"
    return 1
  }

  (cd "$home" && "$bin" serve --host "$host" --port "$port" "$@")
}

nbstatus() {
  local home="${NANOBOT_HOME:-/Users/ben/Desktop/nanobot}"
  local bin="$home/.venv/bin/nanobot"

  [[ -x "$bin" ]] || {
    print -u2 "nbstatus: $bin not found. Run: nanobot setup"
    return 1
  }

  (cd "$home" && "$bin" status "$@")
}

dthome() {
  cd "${DEEPTUTOR_HOME:-/Users/ben/Desktop/DeepTutor}"
}

dtcli() {
  local home="${DEEPTUTOR_HOME:-/Users/ben/Desktop/DeepTutor}"
  local bin="$home/.venv/bin/deeptutor"

  [[ -x "$bin" ]] || {
    print -u2 "dtcli: $bin not found. Run: deeptutor setup"
    return 1
  }

  (cd "$home" && "$bin" "$@")
}

dtapi() {
  local home="${DEEPTUTOR_HOME:-/Users/ben/Desktop/DeepTutor}"
  local python_bin="${DEEPTUTOR_PYTHON:-$home/.venv/bin/python}"

  [[ -x "$python_bin" ]] || {
    print -u2 "dtapi: $python_bin not found. Run: deeptutor setup"
    return 1
  }

  (cd "$home" && "$python_bin" -m deeptutor.api.run_server "$@")
}

paphome() {
  cd "${PAPIS_HOME:-/Users/ben/Desktop/papis}"
}

papdoctor() {
  papis doctor "$@"
}

paplist() {
  papis list --all "$@"
}

papserve() {
  papis serve --address "${PAPIS_SERVE_HOST:-127.0.0.1}" --port "${PAPIS_SERVE_PORT:-8888}" "$@"
}

taphome() {
  local home="${TAPTAP_HOME:-/Users/ben/Desktop/taptaptap}"
  [[ "$home" == "/Users/ben/Desktop/taptap" ]] && home="/Users/ben/Desktop/taptaptap"
  cd "$home"
}

tapcli() {
  taptap cli "$@"
}

nwhome() {
  cd "${NOTCHWOW_HOME:-/Users/ben/Desktop/notchwow}"
}

nwtest() {
  notchwow test "$@"
}

nwrun() {
  notchwow run "$@"
}
