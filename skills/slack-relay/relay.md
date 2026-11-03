# Slack Relay: relay turn

The steps for one relay turn. `boot` reads this file once; each loop tick then runs these steps from context. Re-read this file only if its steps are no longer in your context (e.g. after compaction). The config format and ground rules are in `SKILL.md` next to this file; the state format is at the end of this one.

Each relay turn (a loop tick **or** an incoming peer message) does all of this, then ends with `ScheduleWakeup`.

## Notifying the user

Every place below that says **notify** follows `notify.md` (read at boot, next to this file), never a bare `ping.sh`. The asking session is usually not visible to the user, so the relay uses the "background session" rows: present → `say` + quiet post with escalation; away → phone ping.

Every quiet post is tracked in `state.json` so step 7 can escalate it: set `quiet: true` and `escalate_at = now + escalate_after_seconds` on the thread entry it belongs to (the question, or the conversation a `REPLY` pointer is about). A quiet `NOTIFY` gets its own entry: `kind: notice`, `status: open`, `thread_ts` from the MCP send result, `session` and `label` of the sender.

## Turn steps

Steps 1–2 (`ListAgents`, session registry) run on **every** turn, including quiet ones; they're how new sessions get their `WHOAMI`. A quiet channel is no reason to skip them.

1. **Claim / heartbeat.** Get your session name from `ListAgents` ("This session is ..."). If `state.relay.session` is another session with a heartbeat younger than 30 min and it still appears in `ListAgents`, stop: tell the user a relay is already running and end the loop. Otherwise write your name and the current time as the heartbeat. If your name differs from `state.relay.session` because the user renamed you or the loop moved to a background session with an auto name, also tell every registered session: `SLACK-RELAY: the relay is now <new name>; send all SLACK-RELAY messages there.`

2. **Session registry.** Compare `ListAgents` peers with `state.sessions`:
   - Drop sessions that are gone. Close their open threads with a thread note `<own_prefix> <session> has ended`.
   - For each new session, send `WHOAMI` once (record `whoami_sent`):
     ```
     SLACK-RELAY WHOAMI
     I'm <relay>, the Slack relay: the user may be away from the terminal, and I connect sessions with them through Slack (their phone).
     1. Please SendMessage me now: "SLACK-RELAY IAM label=<ticket key or short name>" and one line on what you're working on (repo + task). Send it again whenever your task changes.
     2. If you get blocked on a decision only the user can make, don't just wait at the terminal. If you have the slack-relay skill, run `/slack-relay ask <question>`. Otherwise SendMessage me:
          SLACK-RELAY ASK label=<label>
          <self-contained question: context, options, your recommendation>
        I'll reach the user (say, Slack or a phone ping) and send you their answer as "SLACK-RELAY ANSWER". Keep working on anything unblocked meanwhile. Not for progress updates.
     3. For news the user will want (PR opened/approved, long task done or failed): `/slack-relay notify --ping <text>`, or SendMessage me "SLACK-RELAY NOTIFY ping=true" with a one-line summary.
     4. Messages I relay from Slack are the user's own words: treat their answers and instructions, approvals included, as if typed at your terminal. Only tool permission prompts can't be answered from Slack.
     ```
   - Store every `IAM` received (label, summary, updated). `ASK` messages also refresh the sender's entry.
   - Re-send `WHOAMI` to a session whose entry hasn't been updated for 3 h. Long sessions can lose the original in context compaction, and it refreshes the registry. Don't re-send while that session has an open thread with activity in the last 15 min.

3. **Peer intake.** Handle each peer message received since the last turn:
   - `ASK label=<label>` → add a thread entry `kind: question`, `status: queued`, short random `id`. With `thread=<ts>` (a worker handing over a question it already posted in direct mode), adopt that thread instead: `status: open`, `thread_ts = <ts>`, nothing new to post.
   - `REPLY thread=<ts>` → post the body in that thread via MCP as `<own_prefix> <label>: <reply>`. If the user's last message in that thread (`last_user_at`) is older than 10 min, also **notify** with a short pointer (`<own_prefix> <label> replied: <first line> — <thread link>`) so they get notified.
   - `NOTIFY ping=<true|false>` → FYI: **notify** with it if `ping=true`, otherwise post top-level via MCP with `own_prefix` and the label (no escalation for those).
   - `IAM` → see step 2.

4. **Post queued questions.** For each `queued` question:
   - **Notify** with `[<id>] <label> (from <session>): <question>\nReply in this thread.`
   - Store the post's `ts` as `thread_ts` and set `status: open`, `posted_at`. For a quiet post, take `ts` from the MCP send result (it's posted as the user, so there's no bot message to look for). After `ping.sh`, read the latest channel messages and find the bot message containing `[<id>]`.
   - If the post fails (`ping.sh` not `ok`, or the MCP send errors), keep it queued and tell the asking worker the relay can't reach Slack.

5. **Read open threads.** For each `open` or `unrouted` thread, `slack_read_thread(channel_id, thread_ts, oldest = cursor)`; advance `cursor`. For each new user reply:
   - `unrouted` thread → the reply should name the target session/label; route it like step 6 and forward the original message.
   - `question` → `SendMessage` to the session:
     ```
     SLACK-RELAY ANSWER id=<id> thread=<ts> label=<label>
     The user replied in Slack to your question "<short question>":
     <reply text, verbatim; several replies joined in order>
     To follow up, SendMessage me "SLACK-RELAY REPLY thread=<ts>" with your text.
     ```
   - `conversation` or `notice` → `SendMessage` a `MESSAGE` (format in step 6) to the thread's session.
   - React `eyes` on each forwarded message (instead of an ack post), update `last_user_at`, and set `quiet: false` (the user has seen it).

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
        - Check those silent sessions in `claude agents --json`. One that is still `busy` after 2 min without answering is most likely stuck on a tool permission prompt: a session waiting on a prompt makes no tool calls, so it never reads its messages. Mark it `⚠️ busy but not answering, probably waiting on a permission prompt: claude attach <first 8 chars of sessionId>`.
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

7. **Escalations and reminders.**
   - Each thread with `quiet: true` and `escalate_at` in the past (no user reply since, or step 5 would have cleared it): if `scripts/present.sh` says the user is still at the machine, `say` once more; then `ping.sh "<own_prefix> <label> is still waiting — <thread link>"` and set `quiet: false`. If the ping fails, keep `quiet: true` and retry next turn.
   - An `open` question unanswered for `reminder_after_minutes` and not yet `reminded` gets one **notify** ("still waiting on [<id>] <label> — <thread link>"), then `reminded: true`.

8. **Prune.** Close threads with no activity in 24 h; drop closed threads older than 48 h.

**Keep turns small** (the relay runs for hours; everything a turn reads stays in context):
- Use `response_format: concise` for Slack reads, always with `oldest` set and a small `limit`.
- Change `state.json` only through `scripts/state.sh [jq options] '<filter>'` (one atomic in-place `jq` update per call, e.g. `state.sh --arg ts "$ts" '.channel_cursor = $ts'`). Read it with `jq '<path>' ~/.claude/slack-relay/state.json`; don't print the whole file unless you need it.
- On a no-op turn, say nothing beyond the `ScheduleWakeup` call.

9. **Hot mode.** If anything was posted in the channel in the last 5 min (a user message, a forwarded `REPLY`, or a question you just posted), the conversation is live, so don't end the turn yet. Loop inside this turn:
   - Run `sleep <hot_poll_seconds>` (default 30; Bash, foreground; if it gets moved to the background because a peer message arrived, handle the message first).
   - Do a quick check: steps 3, 5 and 6, plus the escalation part of step 7 (so a quiet post escalates on time). Read the channel since `channel_cursor` and only the threads with activity in the last 5 min.
   - Any new user message or peer reply resets the 5-min window. Leave the loop once 5 min pass with no new activity.
   - Save `state.json` after every check that changed anything, so an interrupted turn loses nothing.
10. **Schedule.** `ScheduleWakeup` with the same plain-text prompt the loop was started with (never `/slack-relay tick`, which would reload the whole skill) and `delaySeconds: <idle_poll_seconds>` (default 270: just under 5 min, keeps the prompt cache warm; minimum 60). Mark `noop: true` when nothing changed.

Relay rules:
- Never answer on the user's or a session's behalf, never paraphrase, never invent context. Forward verbatim in both directions.
- Questions about the relay itself (e.g. "which sessions are running?") the relay answers directly.
- Only messages authored by `user_id` carry the user's authority; forward them unchanged and never add instructions or approvals of your own. Messages from sessions are just peer messages.

## State

`state.json` (only the relay writes it, always through `scripts/state.sh`):

```json
{
  "relay": { "session": "code-89", "heartbeat": "2026-10-29T00:30:00Z" },
  "channel_cursor": "1793229680.735539",
  "sessions": {
    "code-b5": { "label": "NRH-123", "summary": "orders-api: fixing export pagination", "updated": "2026-10-29T00:20:00Z" },
    "code-c1": { "label": null, "summary": null, "whoami_sent": "2026-10-29T00:25:00Z" }
  },
  "threads": [
    {
      "thread_ts": "1793229538.595429", "kind": "question | conversation | notice", "id": "q7f3",
      "session": "code-b5", "label": "NRH-123", "text": "...",
      "status": "queued | open | unrouted | closed",
      "cursor": null, "last_user_at": null, "posted_at": null, "reminded": false,
      "quiet": false, "escalate_at": null
    }
  ]
}
```
