#!/usr/bin/env bash
set -euo pipefail

# Auto-setup on first run after plugin install.
# Creates directories, makes scripts executable, checks dependencies.
# Runs once — subsequent sessions skip via sentinel file.

SENTINEL="$HOME/.agent-chat-setup-done"
CHAT_DIR="$HOME/agent-chat"
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-.}"

# Already set up — skip
[[ -f "$SENTINEL" ]] && exit 0

# 1. Create shared directories
mkdir -p "$CHAT_DIR/messages" "$CHAT_DIR/inbox" "$CHAT_DIR/pids"

# 2. Initialize sessions.json
if [[ ! -f "$CHAT_DIR/sessions.json" ]]; then
  echo '{}' > "$CHAT_DIR/sessions.json"
fi

# 3. Make scripts executable
chmod +x "$PLUGIN_DIR/scripts/"*.sh 2>/dev/null || true
chmod +x "$PLUGIN_DIR/hooks/scripts/"*.sh 2>/dev/null || true
chmod +x "$PLUGIN_DIR/start.sh" 2>/dev/null || true

# 4. Install `agent-chat` CLI command
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
ln -sf "$PLUGIN_DIR/start.sh" "$BIN_DIR/agent-chat"

# 5. Check dependencies
MISSING=()
command -v tmux >/dev/null 2>&1 || MISSING+=("tmux")
command -v jq >/dev/null 2>&1 || MISSING+=("jq")

OS="$(uname -s)"
case "$OS" in
  Darwin) command -v fswatch >/dev/null 2>&1 || MISSING+=("fswatch") ;;
  Linux)  command -v inotifywait >/dev/null 2>&1 || MISSING+=("inotify-tools") ;;
esac

# 6. Mark setup complete
touch "$SENTINEL"

# 7. Output context for Claude (shown via SessionStart additionalContext)
if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "agent-chat plugin auto-setup complete. Directories created and CLI installed to ~/.local/bin/agent-chat."
  echo "MISSING DEPENDENCIES: ${MISSING[*]}. Please install them:"
  case "$OS" in
    Darwin) echo "  brew install ${MISSING[*]}" ;;
    Linux)  echo "  sudo apt install ${MISSING[*]}" ;;
  esac
else
  echo "agent-chat plugin auto-setup complete. Ready to use. Run 'agent-chat <name>' or '/chat join <name>'."
fi
