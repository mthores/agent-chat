#!/usr/bin/env bash
set -euo pipefail

CHAT_DIR="$HOME/agent-chat"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  echo "Usage: watcher.sh <name> <tmux-pane>"
  exit 1
}

[[ $# -lt 2 ]] && usage

NAME="$1"
PANE="$2"
INBOX_DIR="$CHAT_DIR/inbox/$NAME"
LAST_FILE=""

mkdir -p "$INBOX_DIR"

# Detect OS and pick the right file watcher
OS="$(uname -s)"

handle_new_message() {
  local FILE="$1"
  # Only process .md files
  [[ "$FILE" == *.md ]] || return 0

  # Debounce: skip if we just processed this exact file
  [[ "$FILE" == "$LAST_FILE" ]] && return 0
  LAST_FILE="$FILE"

  # Wait briefly for file to be fully written
  sleep 0.2

  # Extract sender from the file
  local SENDER=""
  if [[ -f "$FILE" ]]; then
    SENDER=$(head -1 "$FILE" | sed -n 's/^from: //p')
  fi

  if [[ -z "$SENDER" ]]; then
    SENDER="unknown"
  fi

  # Nudge the tmux pane with a short message that Claude will act on
  # Send text and Enter separately so Claude Code's TUI registers the submit
  tmux send-keys -t "$PANE" -l "New message from @${SENDER}. Check inbox." || true
  sleep 0.1
  tmux send-keys -t "$PANE" Enter || true
}

case "$OS" in
  Darwin)
    if ! command -v fswatch >/dev/null 2>&1; then
      echo "Error: fswatch is required on macOS. Install with: brew install fswatch"
      exit 1
    fi
    ;;
  Linux)
    if ! command -v inotifywait >/dev/null 2>&1; then
      echo "Error: inotifywait is required on Linux. Install with: apt install inotify-tools"
      exit 1
    fi
    ;;
  *)
    echo "Error: Unsupported OS '$OS'. Only macOS and Linux are supported."
    exit 1
    ;;
esac

# Auto-restart loop: if fswatch/inotifywait dies unexpectedly, retry.
while true; do
  case "$OS" in
    Darwin)
      fswatch -0 --event Created "$INBOX_DIR" | while IFS= read -r -d '' FILE; do
        handle_new_message "$FILE"
      done
      ;;
    Linux)
      inotifywait -m -e create --format '%w%f' "$INBOX_DIR" | while IFS= read -r FILE; do
        handle_new_message "$FILE"
      done
      ;;
  esac
  # Brief pause before restarting to avoid tight loops
  sleep 2
done
