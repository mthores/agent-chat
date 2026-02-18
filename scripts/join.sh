#!/usr/bin/env bash
set -euo pipefail

CHAT_DIR="$HOME/agent-chat"
SESSIONS_FILE="$CHAT_DIR/sessions.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "Usage: join.sh <name> [tmux-pane | --new]"
  echo "  name       — session name (e.g. backend, frontend)"
  echo "  tmux-pane  — tmux pane target (auto-detected if inside tmux)"
  echo "  --new      — create a dedicated tmux session ac-<name>"
  exit 1
}

[[ $# -lt 1 ]] && usage

NAME="$1"
PANE="${2:-}"

# Initialize sessions.json early so we can check claimed panes
mkdir -p "$CHAT_DIR"
if [[ ! -f "$SESSIONS_FILE" ]]; then
  echo '{}' > "$SESSIONS_FILE"
fi

# Helper: get list of panes already claimed by OTHER sessions
get_claimed_panes() {
  jq -r --arg self "$NAME" 'to_entries[] | select(.key != $self) | "\(.key)=\(.value.pane)"' "$SESSIONS_FILE" 2>/dev/null || true
}

# Auto-detect or resolve tmux pane
if [[ -z "$PANE" ]]; then
  if [[ -n "${TMUX:-}" ]]; then
    # Already inside tmux — auto-detect current pane
    PANE="$(tmux display-message -p '#{session_name}:#{window_name}')"

    # Check if this pane is already claimed by another session
    CLAIMED_BY=$(jq -r --arg self "$NAME" --arg pane "$PANE" \
      'to_entries[] | select(.key != $self and .value.pane == $pane) | .key' "$SESSIONS_FILE" 2>/dev/null | head -1)
    if [[ -n "$CLAIMED_BY" ]]; then
      echo "Warning: pane '$PANE' is already used by session '$CLAIMED_BY'."
      echo "Creating dedicated session ac-${NAME} instead."
      PANE="--new"
    fi
  else
    # Not inside tmux — auto-create ac-<name>
    PANE="--new"

    # If tmux is available, show existing sessions for context
    if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
      echo "Not inside tmux. Active tmux sessions:"
      CLAIMED=$(get_claimed_panes)
      tmux list-sessions -F '#{session_name}' 2>/dev/null | while read -r sess; do
        tmux list-panes -t "$sess" -F '#{session_name}:#{window_name}' 2>/dev/null | while read -r pane; do
          OWNER=$(echo "$CLAIMED" | grep "=$pane$" | cut -d= -f1)
          if [[ -n "$OWNER" ]]; then
            echo "  $pane  (in use by $OWNER)"
          else
            echo "  $pane"
          fi
        done
      done
      echo ""
    fi

    echo "Creating dedicated tmux session ac-${NAME}..."
  fi
fi

# Handle --new flag: create a dedicated tmux session
if [[ "$PANE" == "--new" ]]; then
  SESSION_NAME="ac-${NAME}"
  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    PANE="${SESSION_NAME}:0"
  else
    tmux new-session -d -s "$SESSION_NAME" -x 200 -y 50
    PANE="${SESSION_NAME}:0"
    echo "Created tmux session '$SESSION_NAME'."
  fi
  echo "Note: To receive live message notifications, attach to this session:"
  echo "  tmux attach -t $SESSION_NAME"
  echo "Or use '/chat inbox' to check messages manually."
fi

# Validate that the chosen pane isn't claimed by another session
CLAIMED_BY=$(jq -r --arg self "$NAME" --arg pane "$PANE" \
  'to_entries[] | select(.key != $self and .value.pane == $pane) | .key' "$SESSIONS_FILE" 2>/dev/null | head -1)
if [[ -n "$CLAIMED_BY" ]]; then
  echo "Error: pane '$PANE' is already claimed by session '$CLAIMED_BY'."
  echo "Each session needs its own tmux pane for message delivery."
  echo "Use: /chat join $NAME --new"
  exit 1
fi

# Create directories
mkdir -p "$CHAT_DIR/messages" "$CHAT_DIR/inbox/$NAME" "$CHAT_DIR/inbox/$NAME/read" "$CHAT_DIR/pids"

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
