#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Config — edit these to match your project
# ---------------------------------------------------------------------------
SESSION_NAME="hw-sec-project"
WINDOWS=("local-1" "local-2")

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $0 [SESSION_NAME]

Description:
  Creates a new tmux session with a predefined window layout for development.
  The session is created with ${WINDOWS[@]} windows and automatically attaches 
  to ${WINDOWS[0]}.

Arguments:
  SESSION_NAME  (optional) Name for the tmux session.
                Defaults to '${SESSION_NAME}' if not provided.

Options:
  -h, --help    Show this help message and exit.

Prerequisites:
  - tmux must be installed and available on \$PATH.

Side-effects:
  - A new tmux session is created with the given name.

Notes:
  This script must be run OUTSIDE of an existing tmux session.
EOF
  exit 0
}

set_tmux_session() {
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    tmux new-session -d -s "$SESSION" -n "${WINDOWS[0]}"
    for window in "${WINDOWS[@]:1}"; do
      tmux new-window -t "$SESSION" -n "$window"
    done
    tmux select-window -t "$SESSION:${WINDOWS[0]}"
  fi
  tmux attach-session -t "$SESSION"
}

main() {
  # Dependency check
  if ! command -v tmux &>/dev/null; then
    echo -e "❌ ${RED}[Error]:${NC} 'tmux' is not installed or not found on \$PATH." >&2
    echo "     Install it with your package manager (e.g., 'brew install tmux' or 'apt install tmux')." >&2
    exit 1
  fi

  if [[ -n "${TMUX:-}" ]]; then
    echo "❌ Error: This Bash script is meant to be executed outside of tmux."
    echo "          Exit or detach from this tmux session, and then run this script."
    exit 1
  fi

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -h | --help)
      usage
      ;;
    *)
      if [[ -z "${SESSION:-}" ]]; then
        SESSION="$1"
        shift
      else
        echo -e "❌ ${RED}[Error]:${NC} Unrecognized argument: $1"
        exit 1
      fi
      ;;
    esac
  done

  SESSION="${SESSION:-${SESSION_NAME}}"
  set_tmux_session
}

main "$@"
