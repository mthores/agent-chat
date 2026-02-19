#!/usr/bin/env bash
set -euo pipefail

# Discover and register pre-existing tmux sessions (e.g., wt/* sessions).
# Scans for sessions matching a pattern, registers them in sessions.json,
# and starts a watcher for each so messages can be delivered.

CHAT_DIR="$HOME/agent-chat"
SESSIONS_FILE="$CHAT_DIR/sessions.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

PATTERN="${1:-wt/}"

# Initialize
mkdir -p "$CHAT_DIR/messages" "$CHAT_DIR/pids"
if [[ ! -f "$SESSIONS_FILE" ]]; then
  echo '{}' > "$SESSIONS_FILE"
fi

# Find matching tmux sessions
SESSIONS=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^${PATTERN}" || true)

if [[ -z "$SESSIONS" ]]; then
  echo "No tmux sessions matching '${PATTERN}*' found."
  exit 0
fi

COUNT=0
SKIPPED=0
while IFS= read -r SESSION_NAME; do
  # Derive agent-chat name from session name.
  # For wt/{repo}/{slug}, use {repo} as the name (natural for @mentions).
  if [[ "$SESSION_NAME" == wt/* ]]; then
    NAME=$(echo "$SESSION_NAME" | cut -d/ -f2)
  else
    NAME="$SESSION_NAME"
  fi

  # Check if this name is already registered
  if jq -e --arg name "$NAME" '.[$name]' "$SESSIONS_FILE" >/dev/null 2>&1; then
    echo "  skip: '$NAME' (already registered)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Get the actual pane target (respects base-index)
  PANE="$(tmux display-message -t "${SESSION_NAME}" -p '#{session_name}:#{window_index}' 2>/dev/null)" || {
    echo "  skip: '$SESSION_NAME' (could not determine pane)"
    SKIPPED=$((SKIPPED + 1))
    continue
  }

  # Create inbox
  mkdir -p "$CHAT_DIR/inbox/$NAME" "$CHAT_DIR/inbox/$NAME/read"

  # Register
  sessions_lock
  TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  UPDATED=$(jq --arg name "$NAME" --arg pane "$PANE" --arg ts "$TIMESTAMP" \
    '.[$name] = {"name": $name, "pane": $pane, "joined_at": $ts}' "$SESSIONS_FILE")
  echo "$UPDATED" > "$SESSIONS_FILE"
  sessions_unlock

  # Start watcher (kill existing first)
  PID_FILE="$CHAT_DIR/pids/$NAME.pid"
  if [[ -f "$PID_FILE" ]]; then
    OLD_PID=$(cat "$PID_FILE")
    kill "$OLD_PID" 2>/dev/null || true
    rm -f "$PID_FILE"
  fi
  pgrep -f "watcher\\.sh $NAME " 2>/dev/null | xargs kill 2>/dev/null || true
  nohup bash "$SCRIPT_DIR/watcher.sh" "$NAME" "$PANE" > /dev/null 2>&1 &
  echo $! > "$PID_FILE"

  echo "  registered: '$NAME' → $PANE (watcher PID: $(cat "$PID_FILE"))"
  COUNT=$((COUNT + 1))
done <<< "$SESSIONS"

echo "Discovered $COUNT session(s)."
if [[ $SKIPPED -gt 0 ]]; then
  echo "Skipped $SKIPPED (already registered or inaccessible)."
fi
