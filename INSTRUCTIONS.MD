# Agent Chat — Claude Code Plugin

## Vision

A Claude Code plugin that enables multiple Claude Code sessions to communicate with each other through a shared message bus. Think "group chat for agents." Each session joins with a name (e.g. "backend", "frontend", "mobile", "infra") and can send directed messages to other sessions using `@name` syntax.

**Key scenarios:**
1. **Manual handover:** Developer finishes work in one session and tells it: "send a handover to @frontend with the API changes"
2. **Planned handover:** During planning, the agent includes a step like "when contract.md is ready, notify @frontend to begin client implementation"
3. **Clarification:** A receiving agent can ask a clarifying question back, like "@backend the contract says `amount` is a string, is that intentional?"

## Architecture

The plugin uses a **file-based message bus** with a companion **watcher process** that delivers messages to idle sessions.

### How it works

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

**Components:**
- `~/agent-chat/` — shared directory (the "chat room")
- `~/agent-chat/inbox/<name>/` — per-session inbox directories (the message queue)
- `~/agent-chat/sessions.json` — registry of active sessions and their tmux pane names
- `agent-chat` CLI command — launcher that handles tmux, session registration, and Claude Code startup
- Bash scripts in `scripts/` — `send.sh`, `inbox.sh`, `join.sh`, `leave.sh`, `history.sh`, `watcher.sh`
- A watcher script — monitors for new messages and uses `tmux send-keys` to nudge the target session
- Plugin skill — teaches Claude Code how and when to use the messaging system
- Plugin slash command — `/chat` for quick manual interactions

## Plugin Directory Structure

```
agent-chat/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── agent-chat/
│       └── SKILL.md
├── commands/
│   └── chat.md
├── hooks/
│   ├── hooks.json
│   └── scripts/
│       └── check-inbox-on-start.sh
├── scripts/
│   ├── join.sh
│   ├── leave.sh
│   ├── send.sh
│   ├── inbox.sh
│   ├── history.sh
│   └── watcher.sh
├── start.sh
└── setup.sh
```

## Getting Started

### Installation

```bash
git clone <repo-url> agent-chat
cd agent-chat
./setup.sh
```

The setup script:
1. Checks for dependencies (`tmux`, `jq`, `fswatch`/`inotifywait`) and offers to install them
2. Creates `~/agent-chat/`, `~/agent-chat/inbox/`, `~/agent-chat/pids/`
3. Initializes `~/agent-chat/sessions.json`
4. Makes all scripts executable
5. Installs the `agent-chat` command to `~/.local/bin/`

### Usage

From any project directory:

```bash
# Terminal 1
cd ~/Code/my-api
agent-chat backend

# Terminal 2
cd ~/Code/my-app
agent-chat frontend
```

Each call creates a dedicated tmux session (`ac-backend`, `ac-frontend`), registers the session, starts the file watcher, and launches Claude Code with the plugin loaded.

Then just tell Claude what to send:
```
Send a message to @frontend: the API contract is ready, GET /tasks returns { id: string, title: string, done: boolean }[]
```

The receiving session gets a nudge automatically and Claude reads the message, summarizes it, and proposes a plan — waiting for user approval before doing any work.

---

## Component Specifications

---

### 1. Plugin Manifest — `.claude-plugin/plugin.json`

```json
{
  "name": "agent-chat",
  "version": "1.0.0",
  "description": "Group chat for Claude Code sessions. Enables agents to send handovers, share contracts, and coordinate across repos using @mentions.",
  "author": {
    "name": "Mikkel"
  },
  "keywords": ["multi-agent", "chat", "handover", "coordination"]
}
```

**Note:** `author.name` must not be empty — Claude Code's plugin validator rejects it.

---

### 2. Skill — `skills/agent-chat/SKILL.md`

This is the core of the plugin. It teaches Claude Code how to communicate with other sessions. The skill should be activated when:
- The user mentions sending information to another agent/session
- The user asks to notify, handover, or coordinate with another session
- The user plans multi-step work that involves other parts of the stack
- The agent receives a message from another session

**The SKILL.md must include these sections:**

#### Messaging conventions
- How to send a message: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/send.sh <@recipient> "<message>"`
- How to check inbox: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/inbox.sh`
- How to view history: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/history.sh [count]`

#### Session identity
The environment variable `AGENT_CHAT_NAME` contains the current session's name. All scripts use this for sender detection with a fallback chain: `AGENT_CHAT_NAME` env var > tmux pane matching > CLI argument.

#### Guardrails (CRITICAL)
These rules prevent runaway agent-to-agent loops:

1. **Never send a message purely in response to receiving a message.** You must do actual work (code changes, file updates, analysis) before sending a follow-up.
2. **Clarifying questions are allowed** but limited to ONE before waiting for a response. Do not send multiple questions in sequence.
3. **Never autonomously start new work** based on a received message without human approval. When you receive a handover, present the plan to the user and wait for confirmation before executing.
4. **When sending a handover, be specific.** Include: what changed, what files were affected, what the recipient needs to do, and any breaking changes or schema details.
5. **Do not broadcast.** Only send messages to sessions that are directly affected by your changes.
6. **If a planned handover is part of a multi-step plan that the user has already approved**, you may send the handover without additional confirmation — but you must still present any response/reply to the user before acting on it.

#### Message format convention
When composing a message, use this structure:
```
## Handover from [your-session-name]

**What changed:**
- Brief description of changes

**Files affected:**
- List of key files

**What you need to do:**
- Clear action items for the recipient

**Schema/Contract details (if applicable):**
- Relevant types, endpoints, request/response shapes

**Breaking changes:**
- Any breaking changes to be aware of
```

#### On receiving a message
When you receive a message notification:
1. Read the message using `inbox.sh`
2. Present the contents to the user with a summary
3. Propose a plan of action based on the message
4. **Wait for user approval before executing any work**
5. If clarification is needed, you may send ONE clarifying question back

---

### 3. Slash Command — `commands/chat.md`

```markdown
---
description: Send and manage agent chat messages
allowed-tools: Bash
---

# /chat command

Manage the agent-chat messaging system.

## Usage patterns:
- `/chat send @frontend "message"` — Send a message to a specific session
- `/chat inbox` — Check for new messages
- `/chat history` — View recent message history
- `/chat who` — List active sessions

Script mapping:
- `send` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/send.sh @recipient "message"`
- `inbox` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/inbox.sh`
- `history` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/history.sh`
- `who` → `jq '.' ~/agent-chat/sessions.json`
```

---

### 4. Hook — `hooks/hooks.json`

Use a `SessionStart` hook to remind the agent to check its inbox when a session begins (in case messages arrived while it was offline):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/check-inbox-on-start.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

The `check-inbox-on-start.sh` script should:
- Check if `~/agent-chat/sessions.json` exists and this session is registered
- Use `AGENT_CHAT_NAME` env var (with tmux pane detection fallback) to identify the session
- If registered, check for unread messages
- If unread messages exist, output a system message like: "You have X unread agent-chat messages. Run: bash ${CLAUDE_PLUGIN_ROOT}/scripts/inbox.sh"

---

### 5. Scripts

All scripts live in `scripts/` and use short names for reliable invocation by Claude Code.

#### `join.sh <name> <tmux-pane>`
- Creates `~/agent-chat/` and `~/agent-chat/inbox/<name>/` if they don't exist
- Registers the session in `~/agent-chat/sessions.json` with: `{ "name": "<name>", "pane": "<tmux-pane>", "joined_at": "<timestamp>" }`
- Kills any existing watcher for this session (via PID file + `pgrep` for orphan cleanup)
- Starts the watcher process in the background for this session

#### `leave.sh [name]`
- Determines session name via: `AGENT_CHAT_NAME` env var > tmux pane matching > CLI argument
- Removes the session from `sessions.json`
- Kills the watcher process for this session

#### `send.sh <@recipient> "<message>"`
- Determines sender via: `AGENT_CHAT_NAME` env var > tmux pane matching
- Validates the recipient exists in `sessions.json`
- Creates a message file: `~/agent-chat/inbox/<recipient>/<timestamp>-from-<sender>.md`
- Message file format:
  ```
  from: <sender>
  to: <recipient>
  timestamp: <ISO timestamp>
  ---
  <message body>
  ```
- Also appends to `~/agent-chat/history.log` for audit trail

#### `inbox.sh [name]`
- Determines session name via: `AGENT_CHAT_NAME` env var > tmux pane matching > CLI argument
- Reads all `.md` files from `~/agent-chat/inbox/<my-name>/`
- Outputs them in chronological order
- Moves read messages to `~/agent-chat/inbox/<my-name>/read/`

#### `history.sh [count]`
- Shows the last N messages from `history.log` (default: 20)

#### `watcher.sh <name> <tmux-pane>`
- Uses `fswatch` (macOS) or `inotifywait` (Linux) to watch `~/agent-chat/inbox/<name>/`
- Includes debounce logic to prevent duplicate notifications from multiple filesystem events
- When a new `.md` file appears:
  - Waits briefly (0.2s) for the file to be fully written
  - Reads the `from` field from the message
  - Sends a lightweight nudge to the tmux pane using `-l` (literal) flag and separate Enter:
    ```bash
    tmux send-keys -t "$PANE" -l "New message from @${SENDER}. Check inbox."
    sleep 0.1
    tmux send-keys -t "$PANE" Enter
    ```
- **Important:** The nudge is kept short to avoid terminal issues. Text and Enter are sent separately so Claude Code's TUI registers the submit.
- Runs as a background process (`nohup ... &`) with PID stored in `~/agent-chat/pids/<name>.pid`

---

### 6. Launcher — `start.sh`

The main entry point, installed as `agent-chat` on PATH by setup.sh. Handles:

1. Resolves the plugin directory (follows symlinks)
2. Runs `setup.sh` if `~/agent-chat/` doesn't exist
3. If already inside tmux: uses the current pane, runs `join.sh`, launches Claude Code in foreground
4. If not in tmux: creates a dedicated tmux session (`ac-<name>`), runs `join.sh`, launches Claude Code inside, and attaches

Each agent gets its own tmux session to avoid the shared-window problem where switching windows in one terminal affects another.

---

### 7. Setup Script — `setup.sh`

An installer that:
1. Checks for dependencies: `tmux`, `jq`, `fswatch` (macOS) or `inotifywait` (Linux)
2. Offers to auto-install missing dependencies via Homebrew (macOS) or apt (Linux)
3. Creates `~/agent-chat/`, `~/agent-chat/messages/`, `~/agent-chat/inbox/`, `~/agent-chat/pids/`
4. Initializes `~/agent-chat/sessions.json` as `{}`
5. Makes all scripts executable
6. Symlinks `start.sh` to `~/.local/bin/agent-chat` so it's available on PATH

---

## Cross-Platform Considerations

- **Linux:** Use `inotifywait` from `inotify-tools` package
- **macOS:** Use `fswatch` (install via `brew install fswatch`)
- The watcher script detects the OS and uses the appropriate tool
- All scripts use bash with POSIX-compatible patterns where possible

---

## Important Design Decisions

### Why file-based instead of a server?
- Zero dependencies beyond basic CLI tools
- Works offline
- No ports to manage or conflicts
- Easy to inspect and debug (just look at the files)
- Survives session crashes (messages persist on disk)

### Why tmux send-keys for delivery?
- Claude Code doesn't have a push API — it only responds to terminal input
- `tmux send-keys` is the only reliable way to inject a prompt into an active Claude Code session
- The nudge is kept short to avoid terminal corruption
- Text and Enter key are sent separately (`-l` flag + sleep + Enter) for reliable submission in Claude Code's TUI

### Why a separate watcher process?
- Claude Code sessions can be idle. Without a watcher, the agent would need to poll its inbox manually.
- The watcher bridges the gap between file writes and terminal input.

### Why separate tmux sessions per agent?
- A shared tmux session causes all attached clients to show the same active window
- Separate sessions (`ac-backend`, `ac-frontend`) keep each terminal independent

### Why `AGENT_CHAT_NAME` env var?
- Scripts need to know the current session name to identify senders and check the right inbox
- Tmux pane detection alone fails outside tmux or in edge cases
- The env var provides a reliable primary identity, with tmux pane matching and CLI arguments as fallbacks

---

## Guardrail Details

The guardrails in the SKILL.md are critical for preventing runaway loops. Here's the reasoning:

**Problem:** Agent A sends a message to Agent B. Agent B processes it and sends a reply. Agent A processes the reply and sends another message. This loops forever, consuming tokens and potentially making unwanted changes.

**Solution — the "work gate":**
- An agent may only send a message after doing concrete work (writing code, updating files, etc.)
- An agent receiving a message must present it to the user and get approval before acting
- Exception: The user can pre-approve a handover as part of a plan ("when you finish step 4, notify @frontend")
- Clarifying questions are limited to one before waiting

**Problem:** Three agents start acting on the same handover simultaneously.

**Solution — directed messages:**
- Messages are always addressed to a specific `@name`
- Agents ignore messages not addressed to them
- No broadcast mechanism exists (intentionally)

---

## Future Enhancements (Out of Scope for v1)

- **Message acknowledgment:** Sender gets notified when recipient reads the message
- **Thread support:** Group related messages by topic/thread ID
- **Priority levels:** Urgent messages that interrupt vs. passive notifications
- **Shared contract files:** Auto-detect changes to contract.md files and notify relevant sessions
- **Web UI:** A simple dashboard showing active sessions and message flow
- **Token-aware summaries:** Compress long handover messages to save context window
