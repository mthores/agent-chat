---
name: chat
description: Send and manage agent chat messages
argument-hint: "<join|leave|send|inbox|history|who> [args]"
allowed-tools: Bash
---

# /chat command

Manage the agent-chat messaging system.

## Usage patterns:
- `/chat join <name>` — Join the chat as a named session
- `/chat leave` — Leave the chat and stop the watcher
- `/chat send @frontend "message"` — Send a message to a specific session
- `/chat inbox` — Check for new messages
- `/chat history` — View recent message history
- `/chat who` — List active sessions

Parse the user's input after `/chat` and execute the appropriate script from `${CLAUDE_PLUGIN_ROOT}/scripts/`.

Script mapping:
- `join` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/join.sh <name>`
- `leave` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/leave.sh`
- `send` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/send.sh @recipient "message"`
- `inbox` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/inbox.sh`
- `history` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/history.sh`
- `who` → `jq '.' ~/agent-chat/sessions.json`

## Handling /chat join restart

If the join script output contains `RESTART_REQUIRED`, it means the user is not inside tmux and the script has:
1. Created a tmux session with Claude already resuming this conversation
2. Registered the session and started the watcher

Tell the user: "I've set up a tmux session with your conversation ready to resume. Please exit this session (Ctrl+C) and run: `tmux attach -t ac-<name>`"

Do NOT ask the user for confirmation — just tell them what to do.
