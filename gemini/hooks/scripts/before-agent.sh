#!/usr/bin/env bash
# Gemini CLI BeforeAgent hook for agent-chat.
# Checks for unread messages before each user prompt.
#
# Gemini hook protocol:
#   - Read (and discard) JSON from stdin
#   - Write ONLY valid JSON to stdout
#   - All logging/debug output must go to stderr

set -euo pipefail

# Consume stdin (Gemini sends JSON hook payload — we don't need it)
cat > /dev/null

# Resolve scripts dir relative to this script's location:
#   gemini/hooks/scripts/ -> gemini/hooks/ -> gemini/ -> repo root -> scripts/
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../../../scripts" && pwd)"

CHAT_DIR="$HOME/agent-chat"
SESSIONS_FILE="$CHAT_DIR/sessions.json"

# No sessions file means agent-chat isn't active — exit quietly
if [[ ! -f "$SESSIONS_FILE" ]]; then
  echo '{}'
  exit 0
fi

# Detect session name: env var > .agent-chat-name file > tmux pane
NAME="${AGENT_CHAT_NAME:-}"
if [[ -z "$NAME" && -f ".agent-chat-name" ]]; then
  NAME="$(cat .agent-chat-name)"
fi
if [[ -z "$NAME" && -n "${TMUX:-}" ]]; then
  CURRENT_PANE="$(tmux display-message -p '#{session_name}:#{window_index}' 2>/dev/null || true)"
  if [[ -n "$CURRENT_PANE" ]]; then
    NAME=$(jq -r --arg pane "$CURRENT_PANE" \
      'to_entries[] | select(.value.pane == $pane) | .key' "$SESSIONS_FILE" 2>/dev/null | head -1 || true)
  fi
fi

# Not a registered session — exit quietly
if [[ -z "$NAME" ]]; then
  echo '{}'
  exit 0
fi

INBOX_DIR="$CHAT_DIR/inbox/$NAME"
if [[ ! -d "$INBOX_DIR" ]]; then
  echo '{}'
  exit 0
fi

# Count unread messages and collect sender names
shopt -s nullglob
MESSAGES=("$INBOX_DIR"/*.md)
shopt -u nullglob

COUNT=${#MESSAGES[@]}

if [[ $COUNT -eq 0 ]]; then
  echo '{}'
  exit 0
fi

# Extract sender names from filenames (format: timestamp-from-sender.md)
SENDERS=""
for f in "${MESSAGES[@]}"; do
  SENDER=$(basename "$f" | sed 's/.*-from-//' | sed 's/\.md$//')
  SENDERS="${SENDERS}@${SENDER} "
done
SENDERS="${SENDERS% }"  # trim trailing space

MSG="URGENT: You have $COUNT unread agent-chat message(s) from ${SENDERS}. Run: bash $SCRIPTS_DIR/inbox.sh"
jq -n --arg ctx "$MSG" '{"hookSpecificOutput":{"additionalContext":$ctx}}'
