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
- `/chat join <name> <tmux-pane>` — Join targeting a specific tmux pane
- `/chat join <name> --new` — Create a new tmux session and join
- `/chat leave` — Leave the chat and stop the watcher
- `/chat send @frontend "message"` — Send a message to a specific session
- `/chat inbox` — Check for new messages
- `/chat history` — View recent message history
- `/chat who` — List active sessions

Parse the user's input after `/chat` and execute the appropriate script from `${CLAUDE_PLUGIN_ROOT}/scripts/`.

Script mapping:
- `join` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/join.sh <name> [tmux-pane | --new]`
- `leave` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/leave.sh`
- `send` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/send.sh @recipient "message"`
- `inbox` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/inbox.sh`
- `history` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/history.sh`
- `who` → `jq '.' ~/agent-chat/sessions.json`

## Handling /chat join when not in tmux

If `join.sh` exits with code 2, the user is NOT inside tmux. The output will contain either:

- `SESSIONS_AVAILABLE` — existing tmux sessions were found. Present the listed panes to the user and ask which one to use. Then re-run: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/join.sh <name> <chosen-pane>`

- `NO_SESSIONS` — no tmux sessions exist. Ask the user if they want to create one. If yes, run: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/join.sh <name> --new`

After `--new`, remind the user they can attach to the tmux session from another terminal to see message notifications: `tmux attach -t ac-<name>`
