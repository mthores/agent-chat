#!/usr/bin/env bash
set -euo pipefail

# Resolve plugin dir from wherever this script lives (even via symlink)
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
PLUGIN_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"

CHAT_DIR="$HOME/agent-chat"

usage() {
  cat <<'EOF'
Usage: agent-chat <name> [project-dir]

Start a Claude Code agent with agent-chat enabled.

Arguments:
  name          — agent name (e.g. backend, frontend, mobile)
  project-dir   — working directory for Claude Code (default: current dir)

Examples:
  cd ~/Code/my-api && agent-chat backend
  cd ~/Code/my-app && agent-chat frontend
EOF
  exit 1
}

[[ $# -lt 1 ]] && usage

NAME="$1"
PROJECT_DIR="${2:-$(pwd)}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# Run setup if needed
if [[ ! -d "$CHAT_DIR" ]]; then
  bash "$PLUGIN_DIR/setup.sh"
fi

# Determine the tmux pane to use for message delivery
if [[ -n "${TMUX:-}" ]]; then
  # Already inside tmux — use current pane
  PANE="$(tmux display-message -p '#{session_name}:#{window_name}')"
else
  # Not in tmux — create a dedicated session and attach
  TMUX_SESSION="ac-${NAME}"
  PANE="${TMUX_SESSION}:${NAME}"

  # Clean up existing session if present
  tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
  tmux new-session -d -s "$TMUX_SESSION" -n "$NAME" -c "$PROJECT_DIR"

  # Join the chat and start watcher before attaching
  bash "$PLUGIN_DIR/scripts/join.sh" "$NAME" "$PANE"

  # Attach and launch Claude Code inside
  tmux send-keys -t "$PANE" "AGENT_CHAT_NAME=$NAME claude --plugin-dir $PLUGIN_DIR" Enter
  exec tmux attach -t "$TMUX_SESSION"
fi

# Inside tmux — join the chat and launch Claude Code in foreground
bash "$PLUGIN_DIR/scripts/join.sh" "$NAME" "$PANE"
cd "$PROJECT_DIR"
AGENT_CHAT_NAME="$NAME" exec claude --plugin-dir "$PLUGIN_DIR"
