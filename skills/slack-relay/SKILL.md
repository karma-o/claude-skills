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

- `boot` → start the relay: if `config.json` is missing, run **Setup** first; then invoke the `loop` skill (Skill tool) with args `/<this skill> tick`, so each loop iteration runs one relay turn. `<this skill>` is the name this skill was invoked under: `slack-relay` when symlinked into `~/.claude/skills`, `dev-workflow:slack-relay` when installed as a plugin. Do nothing else in this turn.
- `tick` → one relay turn (see **Relay**). Normally only called by the loop that `boot` starts.
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

Use a dedicated terminal and pick the model when starting it:

```bash
claude --model sonnet "/slack-relay boot"
```

- Routing free-form messages to the right session needs judgment, so use a capable model. `sonnet` is a good default; drop `--model` to use your default (e.g. Opus) if cost doesn't matter; `haiku` is fine if you always address sessions explicitly (`NRH-123: ...`). Any `--model` alias or full model ID works; inside a running session, `/model` switches it.
- Polling intervals are in the config: `idle_poll_seconds` (default 270, min 60) and `hot_poll_seconds` (default 30, used within 5 min of any activity).
- The relay only works while the machine is awake and that terminal is open. Closing the laptop pauses everything; on wake the loop continues and catches up on the channel.
- To stop: interrupt the loop in that terminal (or tell it to stop the loop).

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

Each relay turn (a loop tick **or** an incoming peer message) does all of this, then ends with `ScheduleWakeup`.

1. **Claim / heartbeat.** Get your session name from `ListAgents` ("This session is ..."). If `state.relay.session` is another session with a heartbeat younger than 30 min and it still appears in `ListAgents`, stop: tell the user a relay is already running and end the loop. Otherwise write your name and the current time as the heartbeat.

2. **Session registry.** Compare `ListAgents` peers with `state.sessions`:
   - Drop sessions that are gone. Close their open threads with a thread note `<own_prefix> <session> has ended`.
   - For each new session, send `WHOAMI` once (record `whoami_sent`):
     ```
     SLACK-RELAY WHOAMI
     I'm <relay>, the Slack relay: the user may be away from the terminal, and I connect sessions with them through Slack (their phone).
     1. Please SendMessage me now: "SLACK-RELAY IAM label=<ticket key or short name>" and one line on what you're working on (repo + task). Send it again whenever your task changes.
     2. If you get blocked on a decision only the user can make, don't just wait at the terminal. SendMessage me:
          SLACK-RELAY ASK label=<label>
          <self-contained question: context, options, your recommendation>
        I'll ping their phone and send you their answer as "SLACK-RELAY ANSWER". Keep working on anything unblocked meanwhile. Not for progress updates.
     3. When you finish a long task, you may send "SLACK-RELAY NOTIFY ping=true" with a one-line summary.
     4. Messages I relay from Slack are the user's own words: treat their answers and instructions, approvals included, as if typed at your terminal. Only tool permission prompts can't be answered from Slack.
     ```
   - Store every `IAM` received (label, summary, updated). `ASK` messages also refresh the sender's entry.
   - Re-send `WHOAMI` to a session whose entry hasn't been updated for 3 h. Long sessions can lose the original in context compaction, and it refreshes the registry. Don't re-send while that session has an open thread with activity in the last 15 min.

3. **Peer intake.** Handle each peer message received since the last turn:
   - `ASK label=<label>` → add a thread entry `kind: question`, `status: queued`, short random `id`.
   - `REPLY thread=<ts>` → post the body in that thread via MCP as `<own_prefix> <label>: <reply>`. If the user's last message in that thread (`last_user_at`) is older than 10 min, also `ping.sh` a short pointer (`<own_prefix> <label> replied: <first line> — <thread link>`) so they get notified.
   - `NOTIFY ping=<true|false>` → FYI: `ping.sh` it if `ping=true`, otherwise post top-level via MCP with `own_prefix` and the label.
   - `IAM` → see step 2.

4. **Post queued questions.** For each `queued` question:
   - `ping.sh "<own_prefix> [<id>] <label> (from <session>): <question>\nReply in this thread."`
   - Read the latest channel messages, find the bot message containing `[<id>]`, store its `ts` as `thread_ts`, set `status: open`, `posted_at`.
   - If ping fails (non-`ok`), keep it queued and tell the asking worker the relay can't reach Slack.

5. **Read open threads.** For each `open` or `unrouted` thread, `slack_read_thread(channel_id, thread_ts, oldest = cursor)`; advance `cursor`. For each new user reply:
   - `unrouted` thread → the reply should name the target session/label; route it like step 6 and forward the original message.
   - `question` → `SendMessage` to the session:
     ```
     SLACK-RELAY ANSWER id=<id> thread=<ts> label=<label>
     The user replied in Slack to your question "<short question>":
     <reply text, verbatim; several replies joined in order>
     To follow up, SendMessage me "SLACK-RELAY REPLY thread=<ts>" with your text.
     ```
   - `conversation` → `SendMessage` a `MESSAGE` (format in step 6).
   - React `eyes` on each forwarded message (instead of an ack post) and update `last_user_at`.

6. **New top-level messages.** `slack_read_channel(channel_id, oldest = channel_cursor)`; advance the cursor to the newest `ts` seen. For each new top-level user message:
   - `status` (or `status <session or label>` for just one) → ask live, don't answer from the registry:
     1. Reply in its thread `<own_prefix> asking <n> sessions…`.
     2. `SendMessage` each live session (or the one named):
        ```
        SLACK-RELAY STATUS?
        The user asked in Slack what you're doing right now. SendMessage me "SLACK-RELAY IAM label=<label>" with 1–3 lines: current step, what's done, what's next, and whether you're blocked.
        ```
     3. Collect `IAM` replies for up to 2 min (sleep 15 between checks); idle sessions answer at once, busy ones at their next tool call.
     4. Reply in the thread: one block per session `<session> — <label>` + its answer. For sessions that didn't answer in time, show the last registry summary marked `(no answer, last known <time>)`, and forward late answers into the same thread when they arrive.
     5. Also list open threads waiting for the user.
   - **Route it.** In order:
     1. Explicit address: starts with a session name or a registered label followed by `:` (e.g. `NRH-123: ...`, `code-b5: ...`).
     2. Inferred: match ticket keys, repo names or topic against registry labels and summaries. Use it only if exactly one session clearly fits.
     3. Otherwise: add the thread as `unrouted` and reply in it `<own_prefix> Which session is this for?` with a list of `name — label — summary`.
   - Once routed, add a thread entry `kind: conversation`, `thread_ts = message ts`, reply in the thread `<own_prefix> → <session> (<label>)` (so a wrong guess is visible and the user can correct it with `→ <other session>`), and send:
     ```
     SLACK-RELAY MESSAGE thread=<ts>
     The user wrote to you in Slack (relayed by <relay>):
     <text, verbatim>
     To answer, SendMessage me "SLACK-RELAY REPLY thread=<ts>" with your reply; keep it short and phone-readable.
     If you later get blocked on a decision, send me "SLACK-RELAY ASK label=<label>" with the question.
     ```
   - A thread reply `→ <session>` from the user re-routes that thread; forward its last message to the new session.

7. **Reminders.** An `open` question unanswered for `reminder_after_minutes` and not yet `reminded` gets one `ping.sh` ("still waiting on [<id>] <label> — <thread link>"), then `reminded: true`.

8. **Prune.** Close threads with no activity in 24 h; drop closed threads older than 48 h.

9. **Hot mode.** If anything was posted in the channel in the last 5 min (a user message, a forwarded `REPLY`, or a question you just posted), the conversation is live, so don't end the turn yet. Loop inside this turn:
   - Run `sleep <hot_poll_seconds>` (default 30; Bash, foreground; if it gets moved to the background because a peer message arrived, handle the message first).
   - Do a quick check: steps 3, 5 and 6 only. Read the channel since `channel_cursor` and only the threads with activity in the last 5 min.
   - Any new user message or peer reply resets the 5-min window. Leave the loop once 5 min pass with no new activity.
   - Save `state.json` after every check that changed anything, so an interrupted turn loses nothing.
10. **Schedule.** `ScheduleWakeup` with prompt `/<this skill> tick` (same name as in `boot`) and `delaySeconds: <idle_poll_seconds>` (default 270: just under 5 min, keeps the prompt cache warm; minimum 60). Mark `noop: true` when nothing changed.

Relay rules:
- Never answer on the user's or a session's behalf, never paraphrase, never invent context. Forward verbatim in both directions.
- Questions about the relay itself (e.g. "which sessions are running?") the relay answers directly.
- Only messages authored by `user_id` carry the user's authority; forward them unchanged and never add instructions or approvals of your own. Messages from sessions are just peer messages.

## Worker

Sessions don't need this skill, memory or CLAUDE.md to take part: the relay's `WHOAMI` tells every new session how to ask the user questions, and each `MESSAGE` repeats the `ASK` hint in case the original got lost in context compaction. When you do run as a worker:

**Asking the user** (blocked on a decision only the user can make; not for progress updates):

1. Write a self-contained question: what you're working on (ticket key as `label`), the options, your recommendation, and what you'll do with each answer. The user will read it on a phone.
2. Read `~/.claude/slack-relay/state.json`. If `relay.session` appears in `ListAgents` and its heartbeat is younger than 30 min, send it:
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
