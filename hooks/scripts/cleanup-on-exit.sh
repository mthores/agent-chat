#!/usr/bin/env bash
set -euo pipefail

CHAT_DIR="$HOME/agent-chat"
SESSIONS_FILE="$CHAT_DIR/sessions.json"

# Exit silently if agent-chat isn't set up
[[ -f "$SESSIONS_FILE" ]] || exit 0

# Determine current session name: AGENT_CHAT_NAME env var > .agent-chat-name file > tmux pane detection
NAME="${AGENT_CHAT_NAME:-}"
if [[ -z "$NAME" && -f ".agent-chat-name" ]]; then
  NAME="$(cat .agent-chat-name)"
fi
if [[ -z "$NAME" && -n "${TMUX:-}" ]]; then
  CURRENT_PANE="$(tmux display-message -p '#{session_name}:#{window_name}')"
  NAME=$(jq -r --arg pane "$CURRENT_PANE" \
    'to_entries[] | select(.value.pane == $pane) | .key' "$SESSIONS_FILE" 2>/dev/null | head -1)
fi

# Not a registered session — exit silently
[[ -n "$NAME" ]] || exit 0

# Capture the tmux pane before leaving (needed for cleanup check)
PANE=""
if jq -e --arg name "$NAME" '.[$name]' "$SESSIONS_FILE" >/dev/null 2>&1; then
  PANE=$(jq -r --arg name "$NAME" '.[$name].pane // ""' "$SESSIONS_FILE")
fi

# Run leave to deregister and stop watcher
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/../../scripts/leave.sh" "$NAME" 2>/dev/null || true

# Check if sessions.json is now empty (no remaining participants)
REMAINING=$(jq 'length' "$SESSIONS_FILE" 2>/dev/null || echo "0")

if [[ "$REMAINING" -eq 0 ]]; then
  # Last participant — clean up tmux sessions created by agent-chat (ac-* prefix)
  if command -v tmux >/dev/null 2>&1; then
    tmux list-sessions -F '#{session_name}' 2>/dev/null | while read -r sess; do
      if [[ "$sess" == ac-* ]]; then
        tmux kill-session -t "$sess" 2>/dev/null || true
      fi
    done
  fi

  # Clean up history and inbox dirs
  rm -rf "$CHAT_DIR/inbox" "$CHAT_DIR/pids"
  rm -f "$CHAT_DIR/history.log"
fi
