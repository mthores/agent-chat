#!/usr/bin/env bash
set -euo pipefail

CHAT_DIR="$HOME/agent-chat"
HISTORY_FILE="$CHAT_DIR/history.log"

COUNT="${1:-20}"

if [[ ! -f "$HISTORY_FILE" ]]; then
  echo "No message history yet."
  exit 0
fi

echo "--- Last $COUNT messages ---"
echo ""
tail -n "$COUNT" "$HISTORY_FILE"
