#!/usr/bin/env bash
set -euo pipefail

# Auto-cleanup when a Claude Code session ends.
# Kills the watcher, removes from sessions.json, cleans up .agent-chat-name.

CHAT_DIR="$HOME/agent-chat"
SESSIONS_FILE="$CHAT_DIR/sessions.json"

[[ -f "$SESSIONS_FILE" ]] || exit 0

# Determine session name: AGENT_CHAT_NAME env var > .agent-chat-name file > tmux pane
NAME="${AGENT_CHAT_NAME:-}"
if [[ -z "$NAME" && -f ".agent-chat-name" ]]; then
  NAME="$(cat .agent-chat-name)"
fi
if [[ -z "$NAME" && -n "${TMUX:-}" ]]; then
  CURRENT_PANE="$(tmux display-message -p '#{session_name}:#{window_name}' 2>/dev/null || true)"
  if [[ -n "$CURRENT_PANE" ]]; then
    NAME=$(jq -r --arg pane "$CURRENT_PANE" \
      'to_entries[] | select(.value.pane == $pane) | .key' "$SESSIONS_FILE" 2>/dev/null | head -1)
  fi
fi

# Not a registered session — nothing to clean up
[[ -n "$NAME" ]] || exit 0

# Kill the watcher process
PID_FILE="$CHAT_DIR/pids/$NAME.pid"
if [[ -f "$PID_FILE" ]]; then
  PID=$(cat "$PID_FILE")
  kill "$PID" 2>/dev/null || true
  rm -f "$PID_FILE"
fi
pgrep -f "watcher\\.sh $NAME " 2>/dev/null | xargs kill 2>/dev/null || true

# Remove from sessions.json
UPDATED=$(jq --arg name "$NAME" 'del(.[$name])' "$SESSIONS_FILE" 2>/dev/null)
echo "$UPDATED" > "$SESSIONS_FILE"

# Clean up .agent-chat-name
if [[ -f ".agent-chat-name" && "$(cat .agent-chat-name)" == "$NAME" ]]; then
  rm -f ".agent-chat-name"
fi

exit 0
