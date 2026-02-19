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

If the join script output contains `RESTART_REQUIRED`, it means the user is not inside tmux. The script has already launched a bootstrap process that creates a tmux session and resumes the conversation via `claude --continue`.

Check the output for `OPENED=true` or `OPENED=false`:

**If `OPENED=true`:** A new terminal pane has opened with the session resuming.
1. Tell the user: "Your conversation is resuming in the new pane. Closing this session."
2. Immediately run `exit` via Bash to close this session.

**If `OPENED=false`:** The terminal could not be opened automatically. The output includes a `BOOTSTRAP=<path>` line.
1. Tell the user: "Exit this session (Ctrl+C) and run: `bash <path>`"

**Important:** Keep script output minimal — the continued session inherits this conversation history. Do NOT include phrases like "close this session" in Bash output, only in your own text responses.
