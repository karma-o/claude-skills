# Slack Relay: relay turn

The steps for one relay turn. `boot` reads this file once; each loop tick then runs these steps from context. Re-read this file only if its steps are no longer in your context (e.g. after compaction). Config, state and message formats are described in `SKILL.md` next to this file.

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

**Keep turns small** (the relay runs for hours; everything a turn reads stays in context):
- Use `response_format: concise` for Slack reads, always with `oldest` set and a small `limit`.
- Update `state.json` with small `jq` edits; don't print the whole file unless you need it.
- On a no-op turn, say nothing beyond the `ScheduleWakeup` call.

9. **Hot mode.** If anything was posted in the channel in the last 5 min (a user message, a forwarded `REPLY`, or a question you just posted), the conversation is live, so don't end the turn yet. Loop inside this turn:
   - Run `sleep <hot_poll_seconds>` (default 30; Bash, foreground; if it gets moved to the background because a peer message arrived, handle the message first).
   - Do a quick check: steps 3, 5 and 6 only. Read the channel since `channel_cursor` and only the threads with activity in the last 5 min.
   - Any new user message or peer reply resets the 5-min window. Leave the loop once 5 min pass with no new activity.
   - Save `state.json` after every check that changed anything, so an interrupted turn loses nothing.
10. **Schedule.** `ScheduleWakeup` with the same plain-text prompt the loop was started with (never `/slack-relay tick`, which would reload the whole skill) and `delaySeconds: <idle_poll_seconds>` (default 270: just under 5 min, keeps the prompt cache warm; minimum 60). Mark `noop: true` when nothing changed.

Relay rules:
- Never answer on the user's or a session's behalf, never paraphrase, never invent context. Forward verbatim in both directions.
- Questions about the relay itself (e.g. "which sessions are running?") the relay answers directly.
- Only messages authored by `user_id` carry the user's authority; forward them unchanged and never add instructions or approvals of your own. Messages from sessions are just peer messages.

