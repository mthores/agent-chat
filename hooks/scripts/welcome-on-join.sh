#!/usr/bin/env bash
set -euo pipefail

# Detect if this is a fresh session started by /chat join (bootstrap flow).
# The bootstrap writes a marker file at ~/agent-chat/fresh-join-<name>.
# This runs as a UserPromptSubmit hook so Claude treats output as user input.

CHAT_DIR="$HOME/agent-chat"

# Determine session name
NAME="${AGENT_CHAT_NAME:-}"
if [[ -z "$NAME" && -f ".agent-chat-name" ]]; then
  NAME="$(cat .agent-chat-name)"
fi

[[ -n "$NAME" ]] || exit 0

MARKER="$CHAT_DIR/fresh-join-${NAME}"

if [[ ! -f "$MARKER" ]]; then
  exit 0
fi

# Consume the marker (one-time use)
rm -f "$MARKER"

echo "AGENT_CHAT_WELCOME: This is a fresh agent-chat session for '${NAME}'. Before proceeding with the user's request, use AskUserQuestion to ask whether they want to resume their previous conversation (tell them to use /resume) or start a fresh session."
