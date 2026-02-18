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

INBOX_DIR="$CHAT_DIR/inbox/$NAME"
[[ -d "$INBOX_DIR" ]] || exit 0

# Count unread messages
shopt -s nullglob
MESSAGES=("$INBOX_DIR"/*.md)
shopt -u nullglob

COUNT=${#MESSAGES[@]}

if [[ $COUNT -gt 0 ]]; then
  echo "You have $COUNT unread agent-chat message(s). Run: bash \${CLAUDE_PLUGIN_ROOT}/scripts/inbox.sh"
fi
