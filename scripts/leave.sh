#!/usr/bin/env bash
set -euo pipefail

CHAT_DIR="$HOME/agent-chat"
SESSIONS_FILE="$CHAT_DIR/sessions.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

if [[ ! -f "$SESSIONS_FILE" ]]; then
  echo "No sessions file found. Nothing to leave."
  exit 0
fi

# Determine current session name from the sessions file by matching the current tmux pane
# First try to get the current tmux pane identifier
# Determine current session name: AGENT_CHAT_NAME env var > .agent-chat-name file > tmux pane > argument
NAME="${AGENT_CHAT_NAME:-}"
if [[ -z "$NAME" && -f ".agent-chat-name" ]]; then
  NAME="$(cat .agent-chat-name)"
fi
if [[ -z "$NAME" && -n "${TMUX:-}" ]]; then
  CURRENT_PANE="$(tmux display-message -p '#{session_name}:#{window_index}')"
  NAME=$(jq -r --arg pane "$CURRENT_PANE" \
    'to_entries[] | select(.value.pane == $pane) | .key' "$SESSIONS_FILE" | head -1)
fi

# Fall back to argument
if [[ -z "$NAME" && $# -ge 1 ]]; then
  NAME="$1"
fi

if [[ -z "$NAME" ]]; then
  echo "Could not determine session name."
  echo "Usage: agent-chat-leave.sh [name]"
  echo ""
  echo "Active sessions:"
  jq -r 'to_entries[] | "  \(.key) (pane: \(.value.pane))"' "$SESSIONS_FILE"
  exit 1
fi

# Kill the watcher process
PID_FILE="$CHAT_DIR/pids/$NAME.pid"
if [[ -f "$PID_FILE" ]]; then
  PID=$(cat "$PID_FILE")
  if kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    echo "Stopped watcher (PID: $PID)"
  fi
  rm -f "$PID_FILE"
fi

# Remove from sessions.json
sessions_lock
UPDATED=$(jq --arg name "$NAME" 'del(.[$name])' "$SESSIONS_FILE")
echo "$UPDATED" > "$SESSIONS_FILE"
sessions_unlock

# Clean up .agent-chat-name file if it matches this session
if [[ -f ".agent-chat-name" && "$(cat .agent-chat-name)" == "$NAME" ]]; then
  rm -f ".agent-chat-name"
fi

echo "Left agent-chat as '$NAME'"
