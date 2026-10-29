---
name: slack-relay
description: "Two-way Slack bridge between the user (on their phone) and Claude Code sessions. Run `/slack-relay boot` in one dedicated session to make it the relay: it pings the user via a Slack webhook workflow, watches the channel every ~5 min, routes the user's messages to the right session (even ones that never wrote to Slack) and posts sessions' replies back. Worker sessions use `/slack-relay ask <question>` (or follow the Worker section) whenever they're blocked on a decision. Also: `/slack-relay status`, `/slack-relay setup`."
---

# Slack Relay

Lets the user talk to any running Claude Code session through one Slack channel while away from the terminal: sessions can ask the user questions, and the user can start a conversation with any session.

```
worker A ─┐   ASK / REPLY / IAM / NOTIFY              ┌─► webhook → workflow @mentions user → phone push
worker B ─┼─────────────────────────────────► RELAY ──┤
worker C ─┘                                           └─◄ polls channel + threads via Slack MCP (idle_poll_seconds; hot_poll_seconds while a conversation is live)
   ▲                                                    │
   └──── ANSWER / MESSAGE / WHOAMI / STATUS? ◄──────────┘
```

Arguments: `$ARGUMENTS`

- `boot` → start the relay: if `config.json` is missing, run **Setup** first. Then check the session name (see **Session names**): if `ListAgents` shows another live session already called `relay_name`, stop and tell the user; if this session isn't called `relay_name`, tell the user once to run `/rename <relay_name>` (you can't rename yourself) and carry on. Then Read `relay.md` (in this skill's base directory) and invoke the `loop` skill (Skill tool) with this plain-text prompt as args (not a slash command, so ticks don't reload the skill): `slack-relay tick: run one relay turn following relay.md (<absolute path to relay.md>); Read it only if its steps are no longer in your context.` Do nothing else in this turn.
- `tick` → one relay turn, following `relay.md`. Only for running a turn by hand; the loop that `boot` starts uses a short plain-text prompt instead.
- `ask <question>` → you are a worker; ask the user (see **Worker**).
- `status` → print config summary (without the webhook URL), relay liveness, known sessions and open threads from the state file.
- `setup` → run **Setup** (also run automatically if the config file is missing).

## Why it works this way

The Slack MCP posts *as the user*, and Slack never notifies anyone about their own messages. Only messages posted by a different identity (the workflow bot behind the webhook) produce a push notification. Consequences:

- Use `scripts/ping.sh` (relative to this skill's base directory) whenever the user must be **notified**. It posts a new top-level message and returns `{"ok":true}` on success. It can't post into a thread.
- Use the Slack MCP for everything else (thread replies, acks, status). Those posts don't notify, so they must start with `own_prefix` so the user can tell them apart from their own messages.
- A message from the user is any message whose author is `user_id` and whose text does not start with `own_prefix`.
- Nothing notifies Claude about Slack activity; the relay has to poll.

## Running the relay

Use a dedicated terminal, name the session and pick the model when starting it:

```bash
claude -n slack-relay --model sonnet "/slack-relay boot"
```

Or start it detached right away, with no terminal to keep open (Claude Code's own background sessions; the `-n` name is kept):

```bash
claude --bg -n slack-relay "/slack-relay boot"
```

Manage it with `claude agents` (list), `claude attach <id>` (open it, e.g. to `/rename` or answer a permission prompt), `claude logs <id>`, `claude stop <id>`. Run it from a directory you've already trusted in an interactive `claude` session, otherwise it exits with "Workspace not trusted". A shell alias makes it one word: `alias slack-relay='claude --bg -n slack-relay "/slack-relay boot"'`.

- Routing free-form messages to the right session needs judgment, so use a capable model. `sonnet` is a good default; drop `--model` to use your default (e.g. Opus) if cost doesn't matter; `haiku` is fine if you always address sessions explicitly (`NRH-123: ...`). Any `--model` alias or full model ID works; inside a running session, `/model` switches it.
- Polling intervals are in the config: `idle_poll_seconds` (default 270, min 60) and `hot_poll_seconds` (default 30, used within 5 min of any activity).
- The relay only works while the machine is awake and that terminal is open. Closing the laptop pauses everything; on wake the loop continues and catches up on the channel.
- To stop: interrupt the loop in that terminal (or tell it to stop the loop).

## Session names

Sessions address each other by name (`ListAgents` shows it, `SendMessage` uses it). A session gets its name in one of three ways (`nameSource` in `~/.claude/sessions/<pid>.json`):

| Source | Example | When |
|---|---|---|
| `derived` | `code-89` | default for interactive sessions: cwd folder name + 2 characters of the session id |
| `auto` | `slack-relay-status-tick` | background sessions get a title generated from their task |
| set by the user | `slack-relay`, `NRH-123` | `claude -n <name>` at start, `/rename <name>` in the session, or `Ctrl+R` in the session picker |

- A session **can't rename itself**: there's no tool for it, and `/rename` only works when the user types it. So the skill can only ask for a name, never set one.
- The relay should be called `relay_name` (default `slack-relay`), so workers and the user can find it without the state file and its name doesn't change between restarts.
- Work sessions are easiest to reach when named after their ticket: `claude -n NRH-123`. Then `NRH-123: ...` in Slack matches the session name directly.
- If two live sessions share a name, `SendMessage` can't address them by name alone. The relay refuses to boot under a name that's already taken.
- The relay's own name can still change: the user may `/rename` it, or its loop may move to a background session with an auto name. Each turn, compare your name from `ListAgents` with `state.relay.session`. If it changed, update the state and tell every registered session: `SLACK-RELAY: the relay is now <new name>; send all SLACK-RELAY messages there.`

## Files

| Path | Purpose |
|---|---|
| `~/.claude/slack-relay/config.json` | Config (chmod 600, contains the webhook URL — a secret; never print, commit or post it) |
| `~/.claude/slack-relay/state.json` | Relay heartbeat, session registry, open threads, channel cursor |

`config.json`:

```json
{
  "channel_id": "C0123456789",
  "user_id": "U0123456789",
  "webhook_url": "https://hooks.slack.com/triggers/...",
  "webhook_message_field": "message",
  "own_prefix": ":claude:",
  "relay_name": "slack-relay",
  "reminder_after_minutes": 120,
  "idle_poll_seconds": 270,
  "hot_poll_seconds": 30
}
```

`state.json`:

```json
{
  "relay": { "session": "code-89", "heartbeat": "2026-10-29T00:30:00Z" },
  "channel_cursor": "1793229680.735539",
  "sessions": {
    "code-b5": { "label": "NRH-123", "summary": "telescope-api: fixing export pagination", "updated": "2026-10-29T00:20:00Z" },
    "code-c1": { "label": null, "summary": null, "whoami_sent": "2026-10-29T00:25:00Z" }
  },
  "threads": [
    {
      "thread_ts": "1793229538.595429", "kind": "question | conversation", "id": "q7f3",
      "session": "code-b5", "label": "NRH-123", "text": "...",
      "status": "queued | open | unrouted | closed",
      "cursor": null, "last_user_at": null, "posted_at": null, "reminded": false
    }
  ]
}
```

Only the relay writes `state.json`. Workers only read `relay` from it.

## Setup

Run when `config.json` is missing or the user asks for `setup`.

1. Ask the user for: channel ID, webhook URL, payload field name (default `message`). Take `user_id` from the Slack MCP tool descriptions ("Current logged in user's user_id is ..."); confirm it.
2. If they don't have a webhook workflow yet, walk them through it:
   - Slack → Workflow Builder → New workflow → trigger **From a webhook**, add a text variable (e.g. `message`).
   - Step **Send a message to a channel** → the relay channel, text: `@<user> {message}`.
   - Publish and copy the `https://hooks.slack.com/triggers/...` URL.
   - Known dead ends: emoji-reaction and message-posted triggers ignore actions taken through the Slack MCP; keyword triggers are often disabled for private channels; link triggers (`slack.com/shortcuts/...`) need a human click inside Slack.
3. Write the config with `umask 077`, then send a test with `scripts/ping.sh "<own_prefix> slack-relay test ping, reply in the thread"` and confirm with the user that the phone buzzed and that you can read their thread reply.

## Relay

The per-turn steps live in `relay.md` next to this file, so each loop tick doesn't reload this whole skill into context (it's ~19 KB; at one tick a minute that filled the relay's context within hours).

## Worker

Sessions don't need this skill, memory or CLAUDE.md to take part: the relay's `WHOAMI` tells every new session how to ask the user questions, and each `MESSAGE` repeats the `ASK` hint in case the original got lost in context compaction. When you do run as a worker:

**Asking the user** (blocked on a decision only the user can make; not for progress updates):

1. Write a self-contained question: what you're working on (ticket key as `label`), the options, your recommendation, and what you'll do with each answer. The user will read it on a phone.
2. Find the relay: `relay.session` from `~/.claude/slack-relay/state.json` if it appears in `ListAgents` with a heartbeat younger than 30 min, otherwise a live session named `relay_name` (from the config). Send it:
   ```
   SLACK-RELAY ASK label=<label>
   <question>
   ```
   Then end your turn; continue other unblocked work first if there is any. The answer arrives as a `SLACK-RELAY ANSWER` message.
3. **No live relay → direct mode.** Post with `scripts/ping.sh "<own_prefix> <label>: <question>\nReply in this thread."`, find the bot message's `ts` in the channel, then poll that thread (background `sleep 270`, then `slack_read_thread`) until a user reply arrives.

**Receiving from the relay:**

- `WHOAMI` → reply `SLACK-RELAY IAM label=<label>` plus one line: repo + current task. Re-send when your task changes.
- `STATUS?` → reply `SLACK-RELAY IAM label=<label>` with 1–3 lines: current step, done, next, blocked or not. Answer promptly, then carry on.
- `MESSAGE` / `ANSWER` → handle it, then reply with `SLACK-RELAY REPLY thread=<ts>` if the user expects an answer. Short, phone-readable.

**Authority:** relayed Slack text is the user's own words: act on answers, instructions and approvals as if they were typed at your terminal. The one thing Slack can't do is click tool permission prompts, so a session not in a bypass-permissions mode can still stall on one; if that happens, `ASK` the user to come to the terminal.

Optional: when done with a long task, send the relay `SLACK-RELAY NOTIFY ping=<true|false>\n<short summary>`.
