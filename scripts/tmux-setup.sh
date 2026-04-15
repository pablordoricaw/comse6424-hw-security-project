#!/usr/bin/env bash
set -euo pipefail

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
  The session is created with two named windows (window-1, window-2) and
  automatically attaches to it.

Arguments:
  SESSION_NAME  (optional) Name for the tmux session.
                Defaults to 'name-me' if not provided.

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

# ---------------------------------------------------------------------------
# Help flag check
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    usage
fi

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------
if ! command -v tmux &>/dev/null; then
    echo -e "❌ ${RED}[Error]:${NC} 'tmux' is not installed or not found on \$PATH." >&2
    echo "         Install it with your package manager (e.g., 'brew install tmux' or 'apt install tmux')." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
SESSION="${1:-'name-me'}"

set_tmux_session() {
    tmux new-session -d -s "$SESSION" -n window-1
    tmux new-window  -t "$SESSION" \; rename-window window-2

    tmux select-window -t window-1

    tmux attach-session -t "$SESSION"
    tmux select-window -t "$SESSION:window-1"
}

if [[ -n "${TMUX:-}" ]]; then
    echo "❌ Error: This Bash script is meant to be executed outside of tmux."
    echo "          Exit tmux, and then run this script."
    exit 1
else
    set_tmux_session
fi
