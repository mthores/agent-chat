---
description: Send and manage agent chat messages
allowed-tools: Bash
---

# /chat command

Manage the agent-chat messaging system.

## Usage patterns:
- `/chat join <name>` — Join the chat as a named session (requires tmux)
- `/chat leave` — Leave the chat and stop the watcher
- `/chat send @frontend "message"` — Send a message to a specific session
- `/chat inbox` — Check for new messages
- `/chat history` — View recent message history
- `/chat who` — List active sessions

Parse the user's input after `/chat` and execute the appropriate script from `${CLAUDE_PLUGIN_ROOT}/scripts/`.

Script mapping:
- `join` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/join.sh <name>` (tmux pane auto-detected)
- `leave` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/leave.sh`
- `send` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/send.sh @recipient "message"`
- `inbox` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/inbox.sh`
- `history` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/history.sh`
- `who` → `jq '.' ~/agent-chat/sessions.json`
