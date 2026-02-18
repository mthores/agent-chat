#!/usr/bin/env bash
set -euo pipefail

# Check for unread messages on every user prompt.
# Output goes to additionalContext so Claude knows about pending messages.

CHAT_DIR="$HOME/agent-chat"
SESSIONS_FILE="$CHAT_DIR/sessions.json"

[[ -f "$SESSIONS_FILE" ]] || exit 0

# Determine current session name
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

[[ -n "$NAME" ]] || exit 0

INBOX_DIR="$CHAT_DIR/inbox/$NAME"
[[ -d "$INBOX_DIR" ]] || exit 0

# Count unread messages
shopt -s nullglob
MESSAGES=("$INBOX_DIR"/*.md)
shopt -u nullglob

COUNT=${#MESSAGES[@]}

if [[ $COUNT -gt 0 ]]; then
  # Show sender names from filenames (format: timestamp-from-sender.md)
  SENDERS=""
  for f in "${MESSAGES[@]}"; do
    SENDER=$(basename "$f" | sed 's/.*-from-//' | sed 's/\.md$//')
    SENDERS="${SENDERS}@${SENDER} "
  done
  echo "URGENT: You have $COUNT unread agent-chat message(s) from ${SENDERS}. Run: bash \${CLAUDE_PLUGIN_ROOT}/scripts/inbox.sh"
fi
