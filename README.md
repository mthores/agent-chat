# agent-chat

Group chat for AI CLI sessions. Coordinate work across Claude Code and Gemini CLI with a shared message bus.

## What it does

Enable multiple AI CLI sessions to communicate with each other through a shared message bus. Each session joins with a name (e.g., "backend", "frontend", "mobile") and can send directed messages to other sessions. Works across platforms — a Claude Code session can message a Gemini CLI session and vice versa. Perfect for coordinating handovers, sharing contracts, and syncing work across repositories.

## Architecture

```
┌──────────────────┐     writes to      ┌──────────────────┐     watcher detects     ┌──────────────────┐
│   Backend Claude │ ──────────────────>│   ~/agent-chat/  │ ────────────────────>   │   Frontend Gemini │
│   Code (tmux)    │                    │   inbox/         │                         │   CLI (tmux)      │
│                  │ <──────────────────│                  │ <───────────────────    │                   │
└──────────────────┘     watcher detects └──────────────────┘     writes to           └──────────────────┘
                                            │
                                            │  watcher detects / writes to
                                            v
                                     ┌──────────────────┐
                                     │   Mobile Claude  │
                                     │   Code (tmux)    │
                                     └──────────────────┘
```

File-based message bus with automatic delivery via filesystem watcher. All sessions share the same `~/agent-chat/` directory, `sessions.json` registry, and inbox structure.

## Dependencies

Required for both Claude Code and Gemini CLI:

```bash
# macOS
brew install tmux jq fswatch

# Linux
sudo apt install tmux jq inotify-tools
```

## Installation

### Claude Code

#### Option A: Plugin marketplace (recommended)

Install as a Claude Code plugin — works in every session automatically:

```
/plugin marketplace add mthores/agent-chat
/plugin install agent-chat@agent-chat-marketplace
```

On first session start, the plugin automatically sets up directories and checks for dependencies. If any are missing, Claude will tell you what to install.

#### Option B: Manual clone

```bash
git clone https://github.com/mthores/agent-chat.git
cd agent-chat
./setup.sh
```

#### Permissions setup (recommended)

By default, Claude Code prompts for permission each time the plugin runs a bash command. To auto-allow all agent-chat script operations, add these patterns to your global settings:

**File:** `~/.claude/settings.json`

Add these entries to `permissions.allow`:

```json
"Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/*.sh*)",
"Bash(${CLAUDE_PLUGIN_ROOT}/scripts/*.sh*)",
"Bash(bash *agent-chat*/scripts/*.sh*)",
"Bash(*agent-chat*/scripts/*.sh*)"
```

The patterns with the `bash` prefix match explicit `bash script.sh` invocations, while the patterns without it match direct `script.sh` invocations. The `${CLAUDE_PLUGIN_ROOT}` variants match the env var form; the `*agent-chat*` variants match expanded paths. Together they cover all agent-chat operations: inbox, send, join, leave, history.

### Gemini CLI

#### Installation

Link the Gemini extension from your cloned repo:

```bash
gemini extensions link /path/to/agent-chat/gemini
```

This makes the `agent-chat` extension available to Gemini CLI. On first use, the extension's `session-start` hook sets up directories and checks dependencies.

#### How Gemini uses agent-chat

Gemini CLI doesn't use slash commands like Claude Code. Instead, Gemini is taught how to use agent-chat via a context file (`GEMINI.md`), which is automatically loaded by the extension. You communicate naturally:

```
Join the chat with name "backend"
Send a message to @frontend with the API contract
Check my inbox for new messages
```

Gemini uses bash to invoke the same underlying scripts as Claude Code.

### Updating

**Claude Code (marketplace):** Plugins update automatically. If cloned manually:

```bash
cd /path/to/agent-chat
git pull
```

**Gemini CLI:** The extension is linked from your repo, so updates are automatic when you `git pull`.

## Usage

### Joining the chat (Claude Code)

Open a Claude Code session in any project directory and join with a name:

```
/chat join backend
```

If you're inside tmux, your pane is auto-detected. If not, a dedicated tmux session (`ac-backend`) is created and a new terminal pane opens automatically — as a vertical split in iTerm2 or Ghostty, or a new window in other terminals. A fresh Claude session starts (no `--continue`, to avoid duplicating conversation history). In iTerm2, the split targets the originating pane by unique session ID and closes the original pane automatically. In Ghostty, the split uses System Events keystrokes (`Cmd+D`) and clipboard paste; the original pane stays open since Ghostty doesn't yet expose session IDs for pane targeting.

The chat name and the tmux session name are fully decoupled — `sessions.json` maps your chosen alias to the underlying tmux pane. This means you can join pre-existing tmux sessions (e.g., `wt/*` worktree sessions) with any alias you like.

Each session gets its own tmux pane — the plugin prevents two sessions from sharing the same pane. When you close Claude, the session is automatically cleaned up.

### Joining the chat (Gemini CLI)

Start Gemini CLI with the extension and join the chat:

```bash
gemini --extension agent-chat
# Inside the session:
Join the chat with name "frontend"
```

Gemini automatically invokes the join script with the name you provide. Like Claude Code, the session is tracked in `sessions.json` and gets its own tmux pane.

### Sending messages

Tell your AI naturally:

```
Send a message to @frontend: the API contract is ready, GET /tasks returns { id: string, title: string, done: boolean }[]
```

The message is delivered to the receiving session regardless of whether it's Claude Code or Gemini CLI. The watcher nudges the target agent, who reads the message, presents it to their user with a summary and proposed plan, then waits for approval before acting.

### Receiving messages

When another session sends you a message:

1. The watcher detects the new file
2. Your AI gets a nudge: "New message from @backend. Check inbox."
3. Your AI reads the message and presents it to you
4. You review and approve the plan before any work starts

**Claude Code:** You can also check manually with `/chat inbox`.
**Gemini CLI:** Ask naturally: "Check my inbox for new messages."

### Leaving the chat

**Claude Code:**
```
/chat leave
```

**Gemini CLI:**
```
Leave the chat
```

This stops the watcher and removes your session. Also happens automatically when you close the CLI.

### Quick commands (Claude Code)

```
/chat join <name>                  # Join the chat
/chat leave                        # Leave the chat
/chat send @frontend "message"     # Send a message
/chat inbox                        # Check for new messages
/chat history                      # View recent message history
/chat who                          # List active sessions
/chat clean                        # Remove stale sessions with dead tmux panes
```

### Alternative: CLI launcher

The plugin also installs an `agent-chat` CLI command that launches Claude Code inside a dedicated tmux session with the plugin pre-loaded:

```bash
cd ~/Code/my-api
agent-chat backend
```

You can also launch Gemini CLI:

```bash
cd ~/Code/my-api
gemini --extension agent-chat
# Then join manually
```

This is useful if you want live push notifications delivered directly into your CLI session.

## How it works

- **File-based message bus:** `~/agent-chat/` is the shared directory. Each session gets a personal inbox at `~/agent-chat/inbox/<name>/`
- **Filesystem watcher:** A background process (fswatch on macOS, inotifywait on Linux) watches each inbox for new files
- **Nudge delivery:** When a message arrives, the watcher uses `tmux send-keys` to inject a notification into the target AI session
- **Auto-setup:** On first session start after install, hooks create directories and check dependencies
- **Auto-cleanup:** On session end, hooks kill the watcher and remove the session (skipped if the session was handed off to a new tmux pane)
- **Persistence:** Messages are stored as markdown files, so everything survives session crashes
- **Session registry:** `~/agent-chat/sessions.json` tracks active sessions, their tmux panes, and which CLI platform they use
- **Cross-platform messaging:** Claude Code and Gemini CLI sessions use the same message bus, inbox structure, and registry — they can message each other freely

## Guardrails

To prevent runaway agent-to-agent loops:

1. An agent may only send a message after doing concrete work (code changes, file updates, etc.)
2. Receiving an agent must present the message to their user and get approval before executing work
3. Clarifying questions are allowed but limited to one before waiting for a response
4. Messages are always directed to a specific `@name` — no broadcasts
5. If a handover is pre-approved as part of a plan, it can be sent automatically, but responses still require user approval

## See Also

- **[skills/agent-chat/SKILL.md](skills/agent-chat/SKILL.md)** — Claude Code skill definition (teaches Claude how to use the system)
- **[gemini/GEMINI.md](gemini/GEMINI.md)** — Gemini CLI context file (teaches Gemini how to use the system)
