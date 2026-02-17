#!/usr/bin/env bash
set -euo pipefail

CHAT_DIR="$HOME/agent-chat"
PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== agent-chat plugin setup ==="
echo ""

# 1. Check dependencies
MISSING=()

if ! command -v tmux >/dev/null 2>&1; then
  MISSING+=("tmux")
fi

if ! command -v jq >/dev/null 2>&1; then
  MISSING+=("jq")
fi

OS="$(uname -s)"
case "$OS" in
  Darwin)
    if ! command -v fswatch >/dev/null 2>&1; then
      MISSING+=("fswatch (install with: brew install fswatch)")
    fi
    ;;
  Linux)
    if ! command -v inotifywait >/dev/null 2>&1; then
      MISSING+=("inotifywait (install with: apt install inotify-tools)")
    fi
    ;;
  *)
    echo "Warning: Unsupported OS '$OS'. The watcher may not work."
    ;;
esac

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "Missing dependencies: ${MISSING[*]}"
  echo ""

  # Attempt auto-install
  case "$OS" in
    Darwin)
      if command -v brew >/dev/null 2>&1; then
        read -r -p "Install missing dependencies via Homebrew? [Y/n] " REPLY
        REPLY="${REPLY:-Y}"
        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
          # Map display names to brew package names
          BREW_PKGS=()
          for dep in "${MISSING[@]}"; do
            case "$dep" in
              tmux)          BREW_PKGS+=("tmux") ;;
              jq)            BREW_PKGS+=("jq") ;;
              fswatch*)      BREW_PKGS+=("fswatch") ;;
            esac
          done
          brew install "${BREW_PKGS[@]}"
          MISSING=()
        fi
      fi
      ;;
    Linux)
      if command -v apt-get >/dev/null 2>&1; then
        read -r -p "Install missing dependencies via apt? [Y/n] " REPLY
        REPLY="${REPLY:-Y}"
        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
          APT_PKGS=()
          for dep in "${MISSING[@]}"; do
            case "$dep" in
              tmux)          APT_PKGS+=("tmux") ;;
              jq)            APT_PKGS+=("jq") ;;
              inotifywait*)  APT_PKGS+=("inotify-tools") ;;
            esac
          done
          sudo apt-get update && sudo apt-get install -y "${APT_PKGS[@]}"
          MISSING=()
        fi
      fi
      ;;
  esac

  if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo ""
    echo "Could not auto-install. Please install manually and re-run this script."
    exit 1
  fi
fi

echo "Dependencies OK: tmux, jq, $([ "$OS" = "Darwin" ] && echo "fswatch" || echo "inotifywait")"

# 2. Create shared directories
mkdir -p "$CHAT_DIR/messages" "$CHAT_DIR/inbox" "$CHAT_DIR/pids"
echo "Created $CHAT_DIR/"

# 3. Initialize sessions.json
if [[ ! -f "$CHAT_DIR/sessions.json" ]]; then
  echo '{}' > "$CHAT_DIR/sessions.json"
  echo "Initialized sessions.json"
else
  echo "sessions.json already exists, skipping"
fi

# 4. Make all scripts executable
chmod +x "$PLUGIN_DIR/scripts/"*.sh
chmod +x "$PLUGIN_DIR/hooks/scripts/"*.sh
echo "Made scripts executable"

# 5. Install `agent-chat` command on PATH
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
ln -sf "$PLUGIN_DIR/start.sh" "$BIN_DIR/agent-chat"
echo "Installed 'agent-chat' command to $BIN_DIR/agent-chat"

# Check if BIN_DIR is on PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo ""
  echo "NOTE: $BIN_DIR is not on your PATH. Add it with:"
  echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
  echo "  source ~/.zshrc"
fi

# 6. Print next steps
echo ""
echo "=== Setup complete ==="
echo ""
echo "Start agents from any project directory:"
echo ""
echo "  cd ~/Code/my-api"
echo "  agent-chat backend"
echo ""
echo "  cd ~/Code/my-app"
echo "  agent-chat frontend"
echo ""
echo "Each agent runs in its own tmux session (ac-backend, ac-frontend, etc.)"
