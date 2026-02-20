#!/usr/bin/env bash
set -euo pipefail

CHAT_DIR="$HOME/agent-chat"
SESSIONS_FILE="$CHAT_DIR/sessions.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

usage() {
  echo "Usage: join.sh <name> [tmux-pane]"
  echo "  name       — session name (e.g. backend, frontend)"
  echo "  tmux-pane  — tmux pane target (auto-detected if inside tmux)"
  exit 1
}

[[ $# -lt 1 ]] && usage

NAME="$1"
PANE="${2:-}"
NEEDS_RESTART=false

# Check for required dependencies before proceeding
MISSING=()
command -v tmux >/dev/null 2>&1 || MISSING+=("tmux")
command -v jq >/dev/null 2>&1 || MISSING+=("jq")
OS="$(uname -s)"
case "$OS" in
  Darwin) command -v fswatch >/dev/null 2>&1 || MISSING+=("fswatch") ;;
  Linux)  command -v inotifywait >/dev/null 2>&1 || MISSING+=("inotify-tools") ;;
esac
if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "MISSING_DEPENDENCIES: ${MISSING[*]}"
  case "$OS" in
    Darwin) echo "Install with: brew install ${MISSING[*]}" ;;
    Linux)  echo "Install with: sudo apt install ${MISSING[*]}" ;;
  esac
  exit 1
fi

# Initialize sessions.json early so we can check claimed panes
mkdir -p "$CHAT_DIR"
if [[ ! -f "$SESSIONS_FILE" ]]; then
  echo '{}' > "$SESSIONS_FILE"
fi

# Auto-detect or resolve tmux pane
if [[ -z "$PANE" ]]; then
  if [[ -n "${TMUX:-}" ]]; then
    # Already inside tmux — auto-detect current pane
    PANE="$(tmux display-message -p '#{session_name}:#{window_index}')"

    # Check if this pane is already claimed by another session
    CLAIMED_BY=$(jq -r --arg self "$NAME" --arg pane "$PANE" \
      'to_entries[] | select(.key != $self and .value.pane == $pane) | .key' "$SESSIONS_FILE" 2>/dev/null | head -1)
    if [[ -n "$CLAIMED_BY" ]]; then
      echo "Warning: pane '$PANE' is already used by session '$CLAIMED_BY'."
      echo "Creating dedicated session ac-${NAME} instead."
      PANE=""
      NEEDS_RESTART=true
    fi
  else
    # Not inside tmux — need to restart in tmux
    NEEDS_RESTART=true
  fi
fi

# When not in tmux (or pane conflict), bootstrap a new terminal with tmux
if [[ "$NEEDS_RESTART" == true ]]; then
  SESSION_NAME="ac-${NAME}"
  CWD="$(pwd)"

  # Pre-create directories so the bootstrap script can use them
  mkdir -p "$CHAT_DIR/messages" "$CHAT_DIR/inbox/$NAME" "$CHAT_DIR/inbox/$NAME/read" "$CHAT_DIR/pids"

  # Kill existing watchers
  PID_FILE="$CHAT_DIR/pids/$NAME.pid"
  if [[ -f "$PID_FILE" ]]; then
    OLD_PID=$(cat "$PID_FILE")
    kill -0 "$OLD_PID" 2>/dev/null && kill "$OLD_PID" 2>/dev/null || true
    rm -f "$PID_FILE"
  fi
  pgrep -f "watcher\\.sh $NAME " 2>/dev/null | xargs kill 2>/dev/null || true

  # Write session name early so it's available after restart
  echo "$NAME" > "$CWD/.agent-chat-name"

  # Write a self-contained bootstrap script that runs in the NEW terminal.
  # This script creates the tmux session, registers, starts watcher, launches claude,
  # and attaches — all from Terminal.app's environment (not Claude's sandbox).
  BOOTSTRAP_SCRIPT="/tmp/ac-bootstrap-${NAME}.sh"
  cat > "$BOOTSTRAP_SCRIPT" <<BOOTEOF
#!/bin/bash

NAME="${NAME}"
SESSION_NAME="${SESSION_NAME}"
CWD="${CWD}"
SCRIPT_DIR="${SCRIPT_DIR}"
CHAT_DIR="${CHAT_DIR}"
SESSIONS_FILE="${SESSIONS_FILE}"

source "\$SCRIPT_DIR/lib.sh"

echo "Setting up agent-chat session '\$NAME'..."

# Kill existing tmux session if present
if tmux has-session -t "\$SESSION_NAME" 2>/dev/null; then
  tmux kill-session -t "\$SESSION_NAME" 2>/dev/null || true
fi

# Create the tmux session
tmux new-session -d -s "\$SESSION_NAME" -c "\$CWD" -x 200 -y 50

# Determine the actual pane target (respects tmux base-index setting)
PANE="\$(tmux display-message -t "\$SESSION_NAME" -p '#{session_name}:#{window_index}')"

# Register the session in sessions.json
sessions_lock
TIMESTAMP="\$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
UPDATED=\$(jq --arg name "\$NAME" --arg pane "\$PANE" --arg ts "\$TIMESTAMP" \
  '.[\$name] = {"name": \$name, "pane": \$pane, "joined_at": \$ts}' "\$SESSIONS_FILE")
echo "\$UPDATED" > "\$SESSIONS_FILE"
sessions_unlock

# Start the watcher
PID_FILE="\$CHAT_DIR/pids/\$NAME.pid"
nohup bash "\$SCRIPT_DIR/watcher.sh" "\$NAME" "\$PANE" > /dev/null 2>&1 &
echo \$! > "\$PID_FILE"

# Keep tmux session alive even if claude exits
tmux set-option -t "\$SESSION_NAME" remain-on-exit on 2>/dev/null || true

# Launch a fresh claude session (no --continue to avoid duplicating conversation history)
tmux send-keys -t "\$PANE" "unset CLAUDECODE && AGENT_CHAT_NAME=\$NAME claude" Enter

echo "Attaching to tmux session '\$SESSION_NAME'..."
sleep 1
exec tmux attach -t "\$SESSION_NAME"
BOOTEOF
  chmod +x "$BOOTSTRAP_SCRIPT"

  # Auto-open a new terminal window running the bootstrap script
  OS="$(uname -s)"
  OPENED=false
  if [[ "$OS" == "Darwin" ]]; then
    TERM_APP="${TERM_PROGRAM:-Terminal}"
    case "$TERM_APP" in
      iTerm*|iTerm2|iTerm.app)
        # Get the session ID from the inherited env var (set by iTerm2 in the
        # shell that launched Claude). This is reliable regardless of which
        # tab/window is focused, unlike "current session of current window".
        if [[ -n "${ITERM_SESSION_ID:-}" ]]; then
          ORIG_SESSION_ID="${ITERM_SESSION_ID#*:}"
        else
          # Fallback: query AppleScript (less reliable if user switched tabs)
          ORIG_SESSION_ID=$(osascript -e 'tell application "iTerm2" to get unique ID of current session of current window' 2>/dev/null)
        fi
        # Split the ORIGINAL session by unique ID (not "current session" which may change)
        osascript -e "tell application \"iTerm2\"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if unique ID of s is \"$ORIG_SESSION_ID\" then
                  tell s to set newSession to (split vertically with same profile)
                  tell newSession to write text \"bash $BOOTSTRAP_SCRIPT\"
                  return
                end if
              end repeat
            end repeat
          end repeat
        end tell" 2>/dev/null && OPENED=true
        # Append close command to bootstrap script (runs after tmux attach exits)
        if [[ -n "$ORIG_SESSION_ID" ]]; then
          # Write a helper script that closes the original pane
          CLOSE_SCRIPT="/tmp/ac-close-orig-${NAME}.sh"
          cat > "$CLOSE_SCRIPT" <<CLOSEEOF
#!/bin/bash
osascript -e 'tell application "iTerm2" to repeat with w in windows' \\
  -e 'repeat with t in tabs of w' \\
  -e 'repeat with s in sessions of t' \\
  -e 'if unique ID of s is "${ORIG_SESSION_ID}" then' \\
  -e 'tell s to close' \\
  -e 'end if' \\
  -e 'end repeat' \\
  -e 'end repeat' \\
  -e 'end repeat' 2>/dev/null
CLOSEEOF
          chmod +x "$CLOSE_SCRIPT"
          # Inject the close command into the bootstrap, before tmux attach
          sed -i '' "s|exec tmux attach|bash $CLOSE_SCRIPT \&\\
exec tmux attach|" "$BOOTSTRAP_SCRIPT"
        fi
        ;;
      *)
        osascript -e "tell application \"Terminal\"
          do script \"bash $BOOTSTRAP_SCRIPT\"
          activate
        end tell" 2>/dev/null && OPENED=true
        ;;
    esac
  elif [[ "$OS" == "Linux" ]]; then
    if command -v gnome-terminal >/dev/null 2>&1; then
      gnome-terminal -- bash "$BOOTSTRAP_SCRIPT" 2>/dev/null && OPENED=true
    elif command -v xterm >/dev/null 2>&1; then
      xterm -e bash "$BOOTSTRAP_SCRIPT" 2>/dev/null &
      OPENED=true
    fi
  fi

  echo "RESTART_REQUIRED"
  echo "SESSION=$SESSION_NAME"
  if [[ "$OPENED" == true ]]; then
    echo "OPENED=true"
  else
    echo "OPENED=false"
    echo "BOOTSTRAP=$BOOTSTRAP_SCRIPT"
  fi
  exit 0
fi

# --- Normal flow: already inside tmux with a valid pane ---

# Validate that the chosen pane isn't claimed by another session
CLAIMED_BY=$(jq -r --arg self "$NAME" --arg pane "$PANE" \
  'to_entries[] | select(.key != $self and .value.pane == $pane) | .key' "$SESSIONS_FILE" 2>/dev/null | head -1)
if [[ -n "$CLAIMED_BY" ]]; then
  echo "Error: pane '$PANE' is already claimed by session '$CLAIMED_BY'."
  echo "Each session needs its own tmux pane for message delivery."
  exit 1
fi

# Create directories
mkdir -p "$CHAT_DIR/messages" "$CHAT_DIR/inbox/$NAME" "$CHAT_DIR/inbox/$NAME/read" "$CHAT_DIR/pids"

# Check if already registered
if jq -e --arg name "$NAME" '.[$name]' "$SESSIONS_FILE" >/dev/null 2>&1; then
  echo "Session '$NAME' is already registered. Updating..."
fi

# Register the session
sessions_lock
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
UPDATED=$(jq --arg name "$NAME" --arg pane "$PANE" --arg ts "$TIMESTAMP" \
  '.[$name] = {"name": $name, "pane": $pane, "joined_at": $ts}' "$SESSIONS_FILE")
echo "$UPDATED" > "$SESSIONS_FILE"
sessions_unlock

# Kill existing watchers for this session
PID_FILE="$CHAT_DIR/pids/$NAME.pid"
if [[ -f "$PID_FILE" ]]; then
  OLD_PID=$(cat "$PID_FILE")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    kill "$OLD_PID" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
fi
pgrep -f "watcher\\.sh $NAME " 2>/dev/null | xargs kill 2>/dev/null || true

# Start the watcher in the background
nohup bash "$SCRIPT_DIR/watcher.sh" "$NAME" "$PANE" > /dev/null 2>&1 &
echo $! > "$PID_FILE"

# Write session name to working directory for other scripts to find
echo "$NAME" > .agent-chat-name

echo "Joined agent-chat as '$NAME' (pane: $PANE)"
echo "Watcher started (PID: $(cat "$PID_FILE"))"
