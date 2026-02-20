#!/usr/bin/env bash
set -euo pipefail

# Remove stale sessions whose tmux panes no longer exist.
# Also kills orphaned watcher processes for removed sessions.

CHAT_DIR="$HOME/agent-chat"
SESSIONS_FILE="$CHAT_DIR/sessions.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

if [[ ! -f "$SESSIONS_FILE" ]]; then
  echo "No sessions file found."
  exit 0
fi

REMOVED=0
KEPT=0

for NAME in $(jq -r 'keys[]' "$SESSIONS_FILE"); do
  PANE=$(jq -r --arg name "$NAME" '.[$name].pane' "$SESSIONS_FILE")
  # Extract tmux session name (everything before the last colon)
  TMUX_SESSION="${PANE%:*}"

  if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "  kept:    '$NAME' (pane $PANE — alive)"
    KEPT=$((KEPT + 1))
  else
    # Kill watcher if running
    PID_FILE="$CHAT_DIR/pids/$NAME.pid"
    if [[ -f "$PID_FILE" ]]; then
      kill "$(cat "$PID_FILE")" 2>/dev/null || true
      rm -f "$PID_FILE"
    fi
    pgrep -f "watcher\\.sh $NAME " 2>/dev/null | xargs kill 2>/dev/null || true

    # Remove from sessions.json
    sessions_lock
    UPDATED=$(jq --arg name "$NAME" 'del(.[$name])' "$SESSIONS_FILE")
    echo "$UPDATED" > "$SESSIONS_FILE"
    sessions_unlock

    echo "  removed: '$NAME' (pane $PANE — tmux session dead)"
    REMOVED=$((REMOVED + 1))
  fi
done

echo ""
echo "Cleaned $REMOVED stale session(s), $KEPT active."
