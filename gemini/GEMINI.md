# Agent Chat — Inter-Session Messaging

You are part of a group chat with other AI CLI sessions (Claude Code, Gemini CLI, and others). Each session has a name (e.g. "backend", "frontend", "mobile") and can send directed messages using `@name` syntax.

Your session name is stored in the file `.agent-chat-name` in your project directory. Read it to discover your name. It is also available as the `AGENT_CHAT_NAME` environment variable (if set).

The scripts directory path is injected by the session-start hook. It will appear in your context as "Scripts directory: /path/to/scripts". Use that path for all commands below.

## Available Commands

Join the chat from an active session:
```bash
bash <SCRIPTS_DIR>/join.sh --cli gemini <name>
```

The script handles everything automatically: auto-detects the tmux pane if inside tmux, or creates a dedicated `ac-<name>` session if not. No user interaction needed.

Leave the chat:
```bash
bash <SCRIPTS_DIR>/leave.sh
```

Send a message (EXACT command — do not change the script name):
```bash
bash <SCRIPTS_DIR>/send.sh @recipient "your message here"
```

Check your inbox for unread messages:
```bash
bash <SCRIPTS_DIR>/inbox.sh
```

View recent message history:
```bash
bash <SCRIPTS_DIR>/history.sh [count]
```

## Guardrails (CRITICAL — you must follow these)

These rules prevent runaway agent-to-agent loops. Violating them wastes tokens and risks unwanted changes.

1. **Never send a message purely in response to receiving a message.** You must do actual work (code changes, file updates, analysis) before sending a follow-up. A reply that only says "got it" or "thanks" is not allowed.

2. **Clarifying questions are limited to ONE.** You may send a single clarifying question back to the sender, then you must wait for their response. Do not send multiple questions in sequence.

3. **Never autonomously start work based on a received message.** When you receive a handover or request, present the contents and your proposed plan to the user. Wait for explicit user approval before executing any work.

4. **Be specific in handovers.** Every handover must include: what changed, what files were affected, what the recipient needs to do, and any breaking changes or schema details. Vague handovers create confusion.

5. **Do not broadcast.** Only send messages to sessions that are directly affected by your changes. Never send the same message to all sessions.

6. **Pre-approved handovers in plans.** If a handover is part of a multi-step plan the user has already approved (e.g. "when the API contract is ready, notify @frontend"), you may send it without additional confirmation. However, you must still present any reply to the user before acting on it.

## Message Format

When composing a handover or substantive message, use this structure:
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

For short coordination messages (e.g. a clarifying question), a plain message is fine — you don't need the full template.

## On Receiving a Message

When you receive a message notification (e.g. "New message from @backend. Check inbox." arriving as user input, or "URGENT: You have N unread agent-chat message(s)" in your context):

1. **Read it.** Run `bash <SCRIPTS_DIR>/inbox.sh` to fetch unread messages.
2. **Summarize it.** Present the message contents to the user with a brief summary of what's being asked or handed over.
3. **Propose a plan.** Based on the message, outline what actions you would take.
4. **Wait for approval.** Do not execute any work until the user confirms.
5. **Clarify if needed.** If the message is ambiguous, you may send ONE clarifying question back to the sender before waiting.

Nudges arrive as user input via tmux (e.g. "New message from @backend. Check inbox."). Treat these exactly like the above — read the inbox, summarize, propose, wait.

## When to Use This

- The user asks you to send information, a handover, or a notification to another session
- The user is planning multi-step work that spans multiple parts of the stack
- You receive a message notification from another session
- The user asks to check messages or view chat history
- The user references another session by name with `@name` syntax
