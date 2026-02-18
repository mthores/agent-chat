#!/usr/bin/env bash
set -euo pipefail

CHAT_DIR="$HOME/agent-chat"
SESSIONS_FILE="$CHAT_DIR/sessions.json"

# Determine current session name: AGENT_CHAT_NAME env var > .agent-chat-name file > tmux pane > argument
NAME="${AGENT_CHAT_NAME:-}"
if [[ -z "$NAME" && -f ".agent-chat-name" ]]; then
  NAME="$(cat .agent-chat-name)"
fi
if [[ -z "$NAME" && -n "${TMUX:-}" ]]; then
  CURRENT_PANE="$(tmux display-message -p '#{session_name}:#{window_name}')"
  NAME=$(jq -r --arg pane "$CURRENT_PANE" \
    'to_entries[] | select(.value.pane == $pane) | .key' "$SESSIONS_FILE" 2>/dev/null | head -1)
fi

# Fall back to argument
if [[ -z "$NAME" && $# -ge 1 ]]; then
  NAME="$1"
fi

if [[ -z "$NAME" ]]; then
  echo "Error: Could not determine your session name."
  echo "Usage: agent-chat-inbox.sh [name]"
  exit 1
fi

INBOX_DIR="$CHAT_DIR/inbox/$NAME"
READ_DIR="$INBOX_DIR/read"
mkdir -p "$READ_DIR"

# Find unread messages (files in inbox, not in read/)
shopt -s nullglob
MESSAGES=("$INBOX_DIR"/*.md)
shopt -u nullglob

if [[ ${#MESSAGES[@]} -eq 0 ]]; then
  echo "No unread messages."
  exit 0
fi

echo "--- ${#MESSAGES[@]} unread message(s) ---"
echo ""

# Sort by filename (which starts with timestamp) and display
for MSG_FILE in $(printf '%s\n' "${MESSAGES[@]}" | sort); do
  echo "=========================================="
  cat "$MSG_FILE"
  echo ""
  echo "=========================================="
  echo ""

  # Move to read
  mv "$MSG_FILE" "$READ_DIR/"
done

echo "All messages marked as read."
