#!/usr/bin/env bash
set -euo pipefail

CHAT_DIR="$HOME/agent-chat"
SESSIONS_FILE="$CHAT_DIR/sessions.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "Usage: join.sh <name> [tmux-pane]"
  echo "  name       — session name (e.g. backend, frontend)"
  echo "  tmux-pane  — tmux pane target (auto-detected if inside tmux)"
  exit 1
}

[[ $# -lt 1 ]] && usage

NAME="$1"
PANE="${2:-}"

# Auto-detect or resolve tmux pane
if [[ -z "$PANE" ]]; then
  if [[ -n "${TMUX:-}" ]]; then
    # Already inside tmux — auto-detect current pane
    PANE="$(tmux display-message -p '#{session_name}:#{window_name}')"
  else
    # Not inside tmux — check for existing sessions or offer to create one
    if command -v tmux >/dev/null 2>&1 && tmux list-sessions 2>/dev/null; then
      # tmux is running with active sessions — list them
      echo ""
      echo "NOT_IN_TMUX"
      echo "SESSIONS_AVAILABLE"
      tmux list-sessions -F '#{session_name}' 2>/dev/null | while read -r sess; do
        # List all panes in this session
        tmux list-panes -t "$sess" -F '#{session_name}:#{window_name}' 2>/dev/null
      done
      echo ""
      echo "To join, pick a tmux pane from the list above and run:"
      echo "  /chat join $NAME <pane>"
      echo ""
      echo "Or create a new tmux session:"
      echo "  /chat join $NAME --new"
      exit 2
    else
      # No tmux server running — offer to create one
      echo "NOT_IN_TMUX"
      echo "NO_SESSIONS"
      echo ""
      echo "No active tmux sessions found."
      echo ""
      echo "To create a new tmux session and join, run:"
      echo "  /chat join $NAME --new"
      exit 2
    fi
  fi
fi

# Handle --new flag: create a dedicated tmux session
if [[ "$PANE" == "--new" ]]; then
  SESSION_NAME="ac-${NAME}"
  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "tmux session '$SESSION_NAME' already exists."
    PANE="${SESSION_NAME}:0"
  else
    tmux new-session -d -s "$SESSION_NAME" -x 200 -y 50
    PANE="${SESSION_NAME}:0"
    echo "Created tmux session '$SESSION_NAME'."
    echo "Attach from another terminal with: tmux attach -t $SESSION_NAME"
  fi
fi

# Create directories
mkdir -p "$CHAT_DIR/messages" "$CHAT_DIR/inbox/$NAME" "$CHAT_DIR/inbox/$NAME/read" "$CHAT_DIR/pids"

# Initialize sessions.json if missing
if [[ ! -f "$SESSIONS_FILE" ]]; then
  echo '{}' > "$SESSIONS_FILE"
fi

# Check if already registered
if jq -e --arg name "$NAME" '.[$name]' "$SESSIONS_FILE" >/dev/null 2>&1; then
  echo "Session '$NAME' is already registered. Updating..."
fi

# Register the session
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
UPDATED=$(jq --arg name "$NAME" --arg pane "$PANE" --arg ts "$TIMESTAMP" \
  '.[$name] = {"name": $name, "pane": $pane, "joined_at": $ts}' "$SESSIONS_FILE")
echo "$UPDATED" > "$SESSIONS_FILE"

# Kill existing watchers for this session
PID_FILE="$CHAT_DIR/pids/$NAME.pid"
if [[ -f "$PID_FILE" ]]; then
  OLD_PID=$(cat "$PID_FILE")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    kill "$OLD_PID" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
fi
# Also kill any orphaned watcher processes for this session name
pgrep -f "watcher\\.sh $NAME " 2>/dev/null | xargs kill 2>/dev/null || true

# Start the watcher in the background
nohup bash "$SCRIPT_DIR/watcher.sh" "$NAME" "$PANE" > /dev/null 2>&1 &
echo $! > "$PID_FILE"

# Write session name to working directory for other scripts to find
echo "$NAME" > .agent-chat-name

echo "Joined agent-chat as '$NAME' (pane: $PANE)"
echo "Watcher started (PID: $(cat "$PID_FILE"))"
