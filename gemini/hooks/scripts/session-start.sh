#!/usr/bin/env bash
# Gemini CLI SessionStart hook for agent-chat.
# Combines first-run setup and inbox check on session open.
#
# Gemini hook protocol:
#   - Read (and discard) JSON from stdin
#   - Write ONLY valid JSON to stdout
#   - All logging/debug output must go to stderr

set -euo pipefail

# Consume stdin (Gemini sends JSON hook payload — we don't need it)
cat > /dev/null

# Resolve paths relative to this script's location:
#   gemini/hooks/scripts/ -> gemini/hooks/ -> gemini/ -> repo root -> scripts/
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../../../scripts" && pwd)"

SENTINEL="$HOME/.agent-chat-setup-done"
CHAT_DIR="$HOME/agent-chat"
SESSIONS_FILE="$CHAT_DIR/sessions.json"

CONTEXT_PARTS=()

# ── First-run setup ────────────────────────────────────────────────────────────
if [[ ! -f "$SENTINEL" ]]; then
  echo "[agent-chat] Running first-time setup..." >&2

  # 1. Create shared directories
  mkdir -p "$CHAT_DIR/messages" "$CHAT_DIR/inbox" "$CHAT_DIR/pids"

  # 2. Initialize sessions.json
  if [[ ! -f "$CHAT_DIR/sessions.json" ]]; then
    echo '{}' > "$CHAT_DIR/sessions.json"
  fi

  # 3. Make scripts executable
  chmod +x "$SCRIPTS_DIR/"*.sh 2>/dev/null || true
  chmod +x "$SCRIPT_DIR/"*.sh 2>/dev/null || true
  chmod +x "$SCRIPTS_DIR/../start.sh" 2>/dev/null || true

  # 4. Install `agent-chat` CLI command
  BIN_DIR="$HOME/.local/bin"
  mkdir -p "$BIN_DIR"
  REPO_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
  ln -sf "$REPO_ROOT/start.sh" "$BIN_DIR/agent-chat" 2>/dev/null || true

  # 5. Check dependencies
  MISSING=()
  command -v tmux >/dev/null 2>&1 || MISSING+=("tmux")
  command -v jq   >/dev/null 2>&1 || MISSING+=("jq")

  OS="$(uname -s)"
  case "$OS" in
    Darwin) command -v fswatch      >/dev/null 2>&1 || MISSING+=("fswatch") ;;
    Linux)  command -v inotifywait  >/dev/null 2>&1 || MISSING+=("inotify-tools") ;;
  esac

  # 6. Mark setup complete
  touch "$SENTINEL"

  if [[ ${#MISSING[@]} -gt 0 ]]; then
    OS_INSTALL_HINT=""
    case "$OS" in
      Darwin) OS_INSTALL_HINT="brew install ${MISSING[*]}" ;;
      Linux)  OS_INSTALL_HINT="sudo apt install ${MISSING[*]}" ;;
    esac
    CONTEXT_PARTS+=("agent-chat first-time setup complete. MISSING DEPENDENCIES: ${MISSING[*]}. Install with: $OS_INSTALL_HINT")
  else
    CONTEXT_PARTS+=("agent-chat first-time setup complete. Ready to use. Run 'agent-chat <name>' or 'bash $SCRIPTS_DIR/join.sh --cli gemini <name>'.")
  fi

  echo "[agent-chat] First-time setup done." >&2
fi

# ── Inbox check ────────────────────────────────────────────────────────────────
# Always inject scripts dir so GEMINI.md can reference it.
SCRIPTS_CONTEXT="Scripts directory: $SCRIPTS_DIR"

if [[ -f "$SESSIONS_FILE" ]]; then
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

  if [[ -n "$NAME" ]]; then
    INBOX_DIR="$CHAT_DIR/inbox/$NAME"
    if [[ -d "$INBOX_DIR" ]]; then
      shopt -s nullglob
      MESSAGES=("$INBOX_DIR"/*.md)
      shopt -u nullglob
      COUNT=${#MESSAGES[@]}

      if [[ $COUNT -gt 0 ]]; then
        CONTEXT_PARTS+=("$SCRIPTS_CONTEXT. You have $COUNT unread message(s). Run: bash $SCRIPTS_DIR/inbox.sh")
      else
        CONTEXT_PARTS+=("$SCRIPTS_CONTEXT")
      fi
    else
      CONTEXT_PARTS+=("$SCRIPTS_CONTEXT")
    fi
  else
    CONTEXT_PARTS+=("$SCRIPTS_CONTEXT")
  fi
else
  CONTEXT_PARTS+=("$SCRIPTS_CONTEXT")
fi

# ── Output JSON ────────────────────────────────────────────────────────────────
if [[ ${#CONTEXT_PARTS[@]} -gt 0 ]]; then
  # Join parts with ". "
  COMBINED=""
  for part in "${CONTEXT_PARTS[@]}"; do
    if [[ -n "$COMBINED" ]]; then
      COMBINED="$COMBINED. $part"
    else
      COMBINED="$part"
    fi
  done
  # Use jq to safely encode the string as JSON
  CONTEXT_JSON="$(jq -n --arg ctx "$COMBINED" '{"hookSpecificOutput":{"additionalContext":$ctx}}')"
  echo "$CONTEXT_JSON"
else
  echo '{}'
fi
