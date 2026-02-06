# agent-chat

Group chat for Claude Code sessions.

## What it does

Enable multiple Claude Code sessions to communicate with each other through a shared message bus. Each session joins with a name (e.g., "backend", "frontend", "mobile") and can send directed messages to other sessions using `@name` syntax. Perfect for coordinating handovers, sharing contracts, and syncing work across repositories.

## Architecture

```
┌──────────────┐     writes to      ┌──────────────────┐     watcher detects     ┌──────────────────┐
│   Backend     │ ──────────────────>│   ~/agent-chat/  │ ────────────────────>   │   Frontend       │
│   Claude Code │                    │   inbox/         │                         │   Claude Code    │
│   (tmux pane) │ <──────────────────│                  │ <───────────────────    │   (tmux pane)    │
└──────────────┘     watcher detects └──────────────────┘     writes to           └──────────────────┘
                                            │
                                            │  watcher detects / writes to
                                            v
                                     ┌──────────────────┐
                                     │   Mobile          │
                                     │   Claude Code     │
                                     │   (tmux pane)     │
                                     └──────────────────┘
```

File-based message bus with automatic delivery via filesystem watcher.

## Installation

```bash
git clone https://github.com/mthores/agent-chat.git agent-chat
cd agent-chat
./setup.sh
```

The setup script checks for dependencies (tmux, jq, fswatch/inotifywait), creates directories, and installs the `agent-chat` command to your PATH.

## Usage

### Starting a new session

From any project directory, start a named Claude Code session:

```bash
cd ~/Code/my-api
agent-chat backend
```

This creates a dedicated tmux session, registers your session with the message bus, and launches Claude Code. Repeat from different directories with different names to start "frontend", "mobile", etc.

### Joining an existing conversation

From a new project, pick up an ongoing conversation:

```bash
cd ~/Code/my-app
agent-chat frontend
```

Your session automatically receives pending messages from other agents.

### Sending messages

Just tell Claude naturally:

```
Send a message to @frontend: the API contract is ready, GET /tasks returns { id: string, title: string, done: boolean }[]
```

Claude reads your message, delivers it to the receiving session, and the watcher nudges the target agent. The receiver gets a notification, reads the message, presents it to their user with a summary and proposed plan, then waits for approval before acting.

### Receiving messages

When another session sends you a message:
1. The watcher detects the new file
2. Claude gets a nudge: "New message from @backend. Check inbox."
3. Claude reads the message and presents it to you
4. You review it and approve the plan before any work starts

### Quick commands

Use `/chat` slash command for manual operations:

```bash
/chat send @frontend "message"     # Send a message
/chat inbox                        # Check for new messages
/chat history                      # View recent message history
/chat who                          # List active sessions
```

## How it works

- **File-based message bus:** `~/agent-chat/` is the shared chat directory. Each session gets a personal inbox: `~/agent-chat/inbox/<name>/`
- **Filesystem watcher:** A background process (fswatch on macOS, inotifywait on Linux) watches each session's inbox for new files
- **Nudge delivery:** When a message arrives, the watcher uses `tmux send-keys` to inject a notification into the target Claude Code session
- **Persistence:** Messages are stored as markdown files, so everything survives session crashes
- **Session registry:** `~/agent-chat/sessions.json` tracks active sessions and their tmux panes

## Requirements

- **tmux** — for session isolation
- **jq** — for JSON processing
- **fswatch** (macOS) — filesystem watcher
- **inotifywait** (Linux) — filesystem watcher (from `inotify-tools`)

The setup script offers to install missing dependencies via Homebrew (macOS) or apt (Linux).

## Guardrails

To prevent runaway agent-to-agent loops:

1. An agent may only send a message after doing concrete work (code changes, file updates, etc.)
2. Receiving an agent must present the message to their user and get approval before executing work
3. Clarifying questions are allowed but limited to one before waiting for a response
4. Messages are always directed to a specific `@name` — no broadcasts
5. If a handover is pre-approved as part of a plan, it can be sent automatically, but responses still require user approval

## See Also

- **[INSTRUCTIONS.md](INSTRUCTIONS.md)** — Complete technical specification and design decisions
- **[skills/agent-chat/SKILL.md](skills/agent-chat/SKILL.md)** — Claude skill definition (teaches Claude Code how to use the system)
