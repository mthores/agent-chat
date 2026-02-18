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

If the join script output contains `RESTART_REQUIRED`, it means the user is not inside tmux. The script has already:
1. Created a tmux session with Claude resuming this conversation via `--continue`
2. Registered the session and started the watcher
3. Attempted to open a new terminal pane/window with the tmux session

If the output says "A new terminal window has opened":
1. Tell the user their conversation is resuming in the new pane.
2. Ask if they want to close this session now using AskUserQuestion with options "Yes, close this session" and "No, keep it open".
3. If they choose yes, run `exit` via Bash to end this session.

If no window opened (fallback), tell the user:
"Exit this session (Ctrl+C) and run: `bash /tmp/ac-bootstrap-<name>.sh`"
