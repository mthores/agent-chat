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
NEEDS_RESTART=false

# Initialize sessions.json early so we can check claimed panes
mkdir -p "$CHAT_DIR"
if [[ ! -f "$SESSIONS_FILE" ]]; then
  echo '{}' > "$SESSIONS_FILE"
fi

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
      PANE=""
      NEEDS_RESTART=true
    fi
  else
    # Not inside tmux — need to restart in tmux
    NEEDS_RESTART=true
  fi
fi

# When not in tmux (or pane conflict), create tmux session with claude --continue
if [[ "$NEEDS_RESTART" == true ]]; then
  SESSION_NAME="ac-${NAME}"
  PANE="${SESSION_NAME}:0"
  CWD="$(pwd)"

  # Create the tmux session
  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
  fi
  tmux new-session -d -s "$SESSION_NAME" -c "$CWD" -x 200 -y 50

  # Register session and start watcher BEFORE launching claude
  mkdir -p "$CHAT_DIR/messages" "$CHAT_DIR/inbox/$NAME" "$CHAT_DIR/inbox/$NAME/read" "$CHAT_DIR/pids"

  # Kill existing watchers
  PID_FILE="$CHAT_DIR/pids/$NAME.pid"
  if [[ -f "$PID_FILE" ]]; then
    OLD_PID=$(cat "$PID_FILE")
    kill -0 "$OLD_PID" 2>/dev/null && kill "$OLD_PID" 2>/dev/null || true
    rm -f "$PID_FILE"
  fi
  pgrep -f "watcher\\.sh $NAME " 2>/dev/null | xargs kill 2>/dev/null || true

  # Register the session
  TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  UPDATED=$(jq --arg name "$NAME" --arg pane "$PANE" --arg ts "$TIMESTAMP" \
    '.[$name] = {"name": $name, "pane": $pane, "joined_at": $ts}' "$SESSIONS_FILE")
  echo "$UPDATED" > "$SESSIONS_FILE"

  # Start the watcher
  nohup bash "$SCRIPT_DIR/watcher.sh" "$NAME" "$PANE" > /dev/null 2>&1 &
  echo $! > "$PID_FILE"

  # Write session name
  echo "$NAME" > "$CWD/.agent-chat-name"

  # Launch claude --continue inside the tmux session
  tmux send-keys -t "$PANE" "AGENT_CHAT_NAME=$NAME claude --continue" Enter

  echo "RESTART_REQUIRED"
  echo "Prepared tmux session '$SESSION_NAME' with Claude resuming your conversation."
  echo "TMUX_SESSION=$SESSION_NAME"
  echo ""
  echo "To switch, exit this session and run:"
  echo "  tmux attach -t $SESSION_NAME"
  exit 0
fi

# --- Normal flow: already inside tmux with a valid pane ---

# Validate that the chosen pane isn't claimed by another session
CLAIMED_BY=$(jq -r --arg self "$NAME" --arg pane "$PANE" \
  'to_entries[] | select(.key != $self and .value.pane == $pane) | .key' "$SESSIONS_FILE" 2>/dev/null | head -1)
if [[ -n "$CLAIMED_BY" ]]; then
  echo "Error: pane '$PANE' is already claimed by session '$CLAIMED_BY'."
  echo "Each session needs its own tmux pane for message delivery."
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
pgrep -f "watcher\\.sh $NAME " 2>/dev/null | xargs kill 2>/dev/null || true

# Start the watcher in the background
nohup bash "$SCRIPT_DIR/watcher.sh" "$NAME" "$PANE" > /dev/null 2>&1 &
echo $! > "$PID_FILE"

# Write session name to working directory for other scripts to find
echo "$NAME" > .agent-chat-name

echo "Joined agent-chat as '$NAME' (pane: $PANE)"
echo "Watcher started (PID: $(cat "$PID_FILE"))"
