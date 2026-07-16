# Shared paths for the personal terminal runtime.

if [[ -z "${BENSHELL_HOME:-}" ]]; then
  _benshell_exports_source="${(%):-%N}"
  export BENSHELL_HOME="${_benshell_exports_source:A:h:h}"
  unset _benshell_exports_source
fi

export NANOBOT_HOME="${NANOBOT_HOME:-/Users/ben/Desktop/nanobot}"
export NANOBOT_RUN_DIR="${NANOBOT_RUN_DIR:-/tmp/nanobot-run}"
export NANOBOT_API_URL="${NANOBOT_API_URL:-http://127.0.0.1:8765}"
export NANOBOT_FRONTEND_URL="${NANOBOT_FRONTEND_URL:-http://127.0.0.1:5173/}"
export NANOBOT_OPENAI_API_HOST="${NANOBOT_OPENAI_API_HOST:-127.0.0.1}"
export NANOBOT_OPENAI_API_PORT="${NANOBOT_OPENAI_API_PORT:-1234}"
export NANOBOT_OPENAI_API_URL="${NANOBOT_OPENAI_API_URL:-http://$NANOBOT_OPENAI_API_HOST:$NANOBOT_OPENAI_API_PORT}"

export DEEPTUTOR_HOME="${DEEPTUTOR_HOME:-/Users/ben/Desktop/DeepTutor}"
export DEEPTUTOR_RUN_DIR="${DEEPTUTOR_RUN_DIR:-/tmp/deeptutor-run}"

export PAPIS_HOME="${PAPIS_HOME:-/Users/ben/Desktop/papis}"
export PAPIS_RUN_DIR="${PAPIS_RUN_DIR:-/tmp/papis-run}"
export PAPIS_LIBRARY_DIR="${PAPIS_LIBRARY_DIR:-$PAPIS_HOME/library}"
export PAPIS_SERVE_HOST="${PAPIS_SERVE_HOST:-127.0.0.1}"
export PAPIS_SERVE_PORT="${PAPIS_SERVE_PORT:-8888}"
export PAPIS_SERVE_URL="${PAPIS_SERVE_URL:-http://$PAPIS_SERVE_HOST:$PAPIS_SERVE_PORT/}"

if [[ -z "${TAPTAP_HOME:-}" || "$TAPTAP_HOME" == "/Users/ben/Desktop/taptap" ]]; then
  export TAPTAP_HOME="/Users/ben/Desktop/taptaptap"
else
  export TAPTAP_HOME
fi
export TAPTAP_CONDA_ENV="${TAPTAP_CONDA_ENV:-taptap}"
export TAPTAP_PYTHON="${TAPTAP_PYTHON:-/Users/ben/miniforge3/envs/$TAPTAP_CONDA_ENV/bin/python}"

export NOTCHWOW_HOME="${NOTCHWOW_HOME:-/Users/ben/Desktop/notchwow}"
export NOTCHWOW_APP_NAME="${NOTCHWOW_APP_NAME:-notchwow}"
