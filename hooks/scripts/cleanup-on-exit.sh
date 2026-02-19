#!/usr/bin/env bash
set -euo pipefail

# Auto-cleanup when a Claude Code session ends.
# Kills the watcher, removes from sessions.json, cleans up .agent-chat-name.

CHAT_DIR="$HOME/agent-chat"
SESSIONS_FILE="$CHAT_DIR/sessions.json"
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$HOOK_DIR/../../scripts/lib.sh"

[[ -f "$SESSIONS_FILE" ]] || exit 0

# Determine session name: AGENT_CHAT_NAME env var > .agent-chat-name file > tmux pane
NAME="${AGENT_CHAT_NAME:-}"
if [[ -z "$NAME" && -f ".agent-chat-name" ]]; then
  NAME="$(cat .agent-chat-name)"
fi
if [[ -z "$NAME" && -n "${TMUX:-}" ]]; then
  CURRENT_PANE="$(tmux display-message -p '#{session_name}:#{window_index}' 2>/dev/null || true)"
  if [[ -n "$CURRENT_PANE" ]]; then
    NAME=$(jq -r --arg pane "$CURRENT_PANE" \
      'to_entries[] | select(.value.pane == $pane) | .key' "$SESSIONS_FILE" 2>/dev/null | head -1)
  fi
fi

# Not a registered session — nothing to clean up
[[ -n "$NAME" ]] || exit 0

# Check if the session was handed off to a different tmux pane (e.g., via /chat join restart).
# If so, don't clean up — the session is still alive in the new pane.
REGISTERED_PANE=$(jq -r --arg name "$NAME" '.[$name].pane // ""' "$SESSIONS_FILE" 2>/dev/null)
if [[ -n "$REGISTERED_PANE" ]]; then
  # If we're in tmux, check if the registered pane matches ours
  if [[ -n "${TMUX:-}" ]]; then
    CURRENT_PANE="$(tmux display-message -p '#{session_name}:#{window_index}' 2>/dev/null || true)"
    if [[ "$REGISTERED_PANE" != "$CURRENT_PANE" ]]; then
      # Session was handed off to a different pane — don't clean up
      exit 0
    fi
  else
    # Not in tmux, but the session is registered to a tmux pane — it was handed off
    # Only clean up if the tmux session is actually dead
    TMUX_SESSION="${REGISTERED_PANE%%:*}"
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
      # tmux session is still alive — don't clean up
      exit 0
    fi
  fi
fi

# Kill the watcher process
PID_FILE="$CHAT_DIR/pids/$NAME.pid"
if [[ -f "$PID_FILE" ]]; then
  PID=$(cat "$PID_FILE")
  kill "$PID" 2>/dev/null || true
  rm -f "$PID_FILE"
fi
pgrep -f "watcher\\.sh $NAME " 2>/dev/null | xargs kill 2>/dev/null || true

# Remove from sessions.json
sessions_lock
UPDATED=$(jq --arg name "$NAME" 'del(.[$name])' "$SESSIONS_FILE" 2>/dev/null)
echo "$UPDATED" > "$SESSIONS_FILE"
sessions_unlock

# Clean up .agent-chat-name
if [[ -f ".agent-chat-name" && "$(cat .agent-chat-name)" == "$NAME" ]]; then
  rm -f ".agent-chat-name"
fi

exit 0
