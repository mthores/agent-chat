#!/usr/bin/env bash
# Gemini CLI SessionEnd hook for agent-chat.
# Kills the watcher, removes from sessions.json, cleans up .agent-chat-name.
#
# Gemini hook protocol:
#   - Read (and discard) JSON from stdin
#   - Write ONLY valid JSON to stdout (best-effort; CLI may not await this)
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

# Source shared helpers (sessions_lock / sessions_unlock)
# shellcheck source=../../../scripts/lib.sh
source "$SCRIPTS_DIR/lib.sh"

# No sessions file — nothing to clean up
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

# Not a registered session — nothing to clean up
if [[ -z "$NAME" ]]; then
  echo '{}'
  exit 0
fi

# ── Handoff detection ──────────────────────────────────────────────────────────
# If the session was handed off to a different tmux pane (e.g. via /chat join
# restart), skip cleanup — the session is still alive in the new pane.
REGISTERED_PANE=$(jq -r --arg name "$NAME" '.[$name].pane // ""' "$SESSIONS_FILE" 2>/dev/null || true)
if [[ -n "$REGISTERED_PANE" ]]; then
  if [[ -n "${TMUX:-}" ]]; then
    CURRENT_PANE="$(tmux display-message -p '#{session_name}:#{window_index}' 2>/dev/null || true)"
    if [[ "$REGISTERED_PANE" != "$CURRENT_PANE" ]]; then
      echo "[agent-chat] Session handed off to $REGISTERED_PANE — skipping cleanup." >&2
      echo '{}'
      exit 0
    fi
  else
    # Not in tmux but session is registered to a tmux pane — it was handed off.
    # Only clean up if the tmux session is actually dead.
    TMUX_SESSION="${REGISTERED_PANE%%:*}"
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
      echo "[agent-chat] tmux session $TMUX_SESSION still alive — skipping cleanup." >&2
      echo '{}'
      exit 0
    fi
  fi
fi

# ── Kill watcher process ───────────────────────────────────────────────────────
PID_FILE="$CHAT_DIR/pids/$NAME.pid"
if [[ -f "$PID_FILE" ]]; then
  PID=$(cat "$PID_FILE")
  kill "$PID" 2>/dev/null || true
  rm -f "$PID_FILE"
  echo "[agent-chat] Killed watcher pid $PID." >&2
fi
pgrep -f "watcher\\.sh $NAME " 2>/dev/null | xargs kill 2>/dev/null || true

# ── Remove from sessions.json ──────────────────────────────────────────────────
sessions_lock
UPDATED=$(jq --arg name "$NAME" 'del(.[$name])' "$SESSIONS_FILE" 2>/dev/null)
echo "$UPDATED" > "$SESSIONS_FILE"
sessions_unlock
echo "[agent-chat] Removed '$NAME' from sessions.json." >&2

# ── Clean up .agent-chat-name ──────────────────────────────────────────────────
if [[ -f ".agent-chat-name" && "$(cat .agent-chat-name)" == "$NAME" ]]; then
  rm -f ".agent-chat-name"
  echo "[agent-chat] Removed .agent-chat-name." >&2
fi

echo '{}'
exit 0
