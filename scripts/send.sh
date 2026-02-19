#!/usr/bin/env bash
set -euo pipefail

CHAT_DIR="$HOME/agent-chat"
SESSIONS_FILE="$CHAT_DIR/sessions.json"

usage() {
  echo "Usage: agent-chat-send.sh [--from <name>] <@recipient> <message>"
  echo "  --from     — sender name (overrides AGENT_CHAT_NAME and tmux detection)"
  echo "  recipient  — target session name (with or without @ prefix)"
  echo "  message    — the message to send"
  exit 1
}

# Parse --from flag
FROM_FLAG=""
if [[ "${1:-}" == "--from" ]]; then
  FROM_FLAG="${2:-}"
  [[ -z "$FROM_FLAG" ]] && usage
  shift 2
fi

[[ $# -lt 2 ]] && usage

# Strip @ prefix if present
RECIPIENT="${1#@}"
shift
MESSAGE="$*"

if [[ ! -f "$SESSIONS_FILE" ]]; then
  echo "Error: No sessions file found. Has anyone joined the chat?"
  exit 1
fi

# Validate recipient exists
if ! jq -e --arg name "$RECIPIENT" '.[$name]' "$SESSIONS_FILE" >/dev/null 2>&1; then
  echo "Error: No session named '$RECIPIENT' is registered."
  echo ""
  echo "Active sessions:"
  jq -r 'keys[]' "$SESSIONS_FILE"
  exit 1
fi

# Determine sender name: --from flag > AGENT_CHAT_NAME env var > .agent-chat-name file > tmux pane detection
SENDER="${FROM_FLAG:-${AGENT_CHAT_NAME:-}}"
if [[ -z "$SENDER" && -f ".agent-chat-name" ]]; then
  SENDER="$(cat .agent-chat-name)"
fi
if [[ -z "$SENDER" && -n "${TMUX:-}" ]]; then
  CURRENT_PANE="$(tmux display-message -p '#{session_name}:#{window_index}')"
  SENDER=$(jq -r --arg pane "$CURRENT_PANE" \
    'to_entries[] | select(.value.pane == $pane) | .key' "$SESSIONS_FILE" | head -1)
fi

if [[ -z "$SENDER" ]]; then
  echo "Error: Could not determine your session name."
  echo "Either set AGENT_CHAT_NAME, create .agent-chat-name in your project dir, or run inside a registered tmux pane."
  exit 1
fi

# Create the message file
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
FILENAME_TS="$(date -u +"%Y%m%d-%H%M%S")"
INBOX_DIR="$CHAT_DIR/inbox/$RECIPIENT"
mkdir -p "$INBOX_DIR"

MSG_FILE="$INBOX_DIR/${FILENAME_TS}-from-${SENDER}.md"

cat > "$MSG_FILE" <<EOF
from: $SENDER
to: $RECIPIENT
timestamp: $TIMESTAMP
---
$MESSAGE
EOF

# Append to history log
mkdir -p "$CHAT_DIR"
echo "[$TIMESTAMP] $SENDER -> @$RECIPIENT: $MESSAGE" >> "$CHAT_DIR/history.log"

echo "Message sent to @$RECIPIENT"
