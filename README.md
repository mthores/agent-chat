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

### Option A: Plugin marketplace (recommended)

Install as a Claude Code plugin — works in every session automatically:

```
/plugin marketplace add mthores/agent-chat
/plugin install agent-chat@agent-chat-marketplace
```

On first session start, the plugin automatically sets up directories and checks for dependencies. If any are missing, Claude will tell you what to install.

### Option B: Manual clone

```bash
git clone https://github.com/mthores/agent-chat.git
cd agent-chat
./setup.sh
```

### Dependencies

```bash
# macOS
brew install tmux jq fswatch

# Linux
sudo apt install tmux jq inotify-tools
```

### Updating

Marketplace plugins update automatically. If cloned manually:

```bash
cd /path/to/agent-chat
git pull
```

### Permissions setup (recommended)

By default, Claude Code prompts for permission each time the plugin runs a bash command. To auto-allow all agent-chat script operations, add these two patterns to your global settings:

**File:** `~/.claude/settings.json`

Add these entries to `permissions.allow`:

```json
"Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/*.sh*)",
"Bash(bash *agent-chat*/scripts/*.sh*)"
```

The first pattern matches when Claude uses the `${CLAUDE_PLUGIN_ROOT}` env var directly. The second matches expanded paths (e.g., `~/.claude/plugins/cache/embla/agent-chat/1.0.0/scripts/inbox.sh`). Together they cover all agent-chat operations: inbox, send, join, leave, history.

Other commands the plugin uses (`jq`, `cat`, `echo`) are typically already in most users' allow lists. If not, add `"Bash(jq *)"` and `"Bash(cat *)"` as well.

## Usage

### Joining the chat

Open a Claude Code session in any project directory and join with a name:

```
/chat join backend
```

If you're inside tmux, your pane is auto-detected. If not, a dedicated tmux session (`ac-backend`) is created and a new terminal pane opens automatically — as a vertical split in iTerm2, or a new window in other terminals. A fresh Claude session starts (no `--continue`, to avoid duplicating conversation history) and the original pane closes automatically. In iTerm2, the split targets the originating pane by unique session ID, so switching tabs before the split completes won't cause it to land in the wrong pane. Repeat in other terminals with different names:

```
/chat join frontend
/chat join mobile
```

Each session gets its own tmux pane — the plugin prevents two sessions from sharing the same pane. When you close Claude, the session is automatically cleaned up.

### Sending messages

Just tell Claude naturally:

```
Send a message to @frontend: the API contract is ready, GET /tasks returns { id: string, title: string, done: boolean }[]
```

Claude delivers the message to the receiving session. The watcher nudges the target agent, who reads the message, presents it to their user with a summary and proposed plan, then waits for approval before acting.

### Receiving messages

When another session sends you a message:
1. The watcher detects the new file
2. Claude gets a nudge: "New message from @backend. Check inbox."
3. Claude reads the message and presents it to you
4. You review and approve the plan before any work starts

You can also check manually with `/chat inbox`.

### Leaving the chat

```
/chat leave
```

This stops the watcher and removes your session. Also happens automatically when you close Claude.

### Quick commands

```
/chat join <name>                  # Join the chat
/chat leave                        # Leave the chat
/chat send @frontend "message"     # Send a message
/chat inbox                        # Check for new messages
/chat history                      # View recent message history
/chat who                          # List active sessions
```

### Alternative: CLI launcher

The plugin also installs an `agent-chat` CLI command that launches Claude Code inside a dedicated tmux session with the plugin pre-loaded:

```bash
cd ~/Code/my-api
agent-chat backend
```

This is useful if you want live push notifications delivered directly into your Claude session.

## How it works

- **File-based message bus:** `~/agent-chat/` is the shared directory. Each session gets a personal inbox at `~/agent-chat/inbox/<name>/`
- **Filesystem watcher:** A background process (fswatch on macOS, inotifywait on Linux) watches each inbox for new files
- **Nudge delivery:** When a message arrives, the watcher uses `tmux send-keys` to inject a notification into the target Claude Code session
- **Auto-setup:** On first session start after install, a `SessionStart` hook creates directories and checks dependencies
- **Auto-cleanup:** On session end, a `SessionEnd` hook kills the watcher and removes the session (skipped if the session was handed off to a new tmux pane)
- **Persistence:** Messages are stored as markdown files, so everything survives session crashes
- **Session registry:** `~/agent-chat/sessions.json` tracks active sessions and their tmux panes

## Guardrails

To prevent runaway agent-to-agent loops:

1. An agent may only send a message after doing concrete work (code changes, file updates, etc.)
2. Receiving an agent must present the message to their user and get approval before executing work
3. Clarifying questions are allowed but limited to one before waiting for a response
4. Messages are always directed to a specific `@name` — no broadcasts
5. If a handover is pre-approved as part of a plan, it can be sent automatically, but responses still require user approval

## See Also

- **[skills/agent-chat/SKILL.md](skills/agent-chat/SKILL.md)** — Claude skill definition (teaches Claude Code how to use the system)
