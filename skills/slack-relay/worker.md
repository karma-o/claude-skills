# Worker commands: `ask` and `notify`

Any session can reach the user with these. Workers always start the conversation themselves. The relay, when one is running, keeps track of threads and passes replies back. When none is running, the worker handles Slack itself.

## Find the relay

A relay is live if `relay.session` from `~/.claude/slack-relay/state.json` appears in `ListAgents` with a heartbeat younger than 30 minutes. Failing that, look for a live session named `relay_name` from the config.

## `ask <question>`

For a decision only the user can make. Not for progress updates.

1. Write a self-contained question: what you're working on (use the ticket key as `label`), the options, your recommendation, and what you'll do with each answer.
2. **Interactive session and the user is present** (see `notify.md` §1): `say` it and ask in your own terminal first, with the escalation timer from `notify.md`. Stop here if they answer.
3. **A relay is live** → `SendMessage` it:
   ```
   SLACK-RELAY ASK label=<label>
   <question>
   ```
   Then carry on with any unblocked work, or end your turn. The answer arrives as `SLACK-RELAY ANSWER id=… thread=…`. Reply to follow-ups with `SLACK-RELAY REPLY thread=<ts>`.
4. **No relay (direct mode):**
   1. Notify following `notify.md`, with the message `<label>: <question>` + newline + `Reply in this thread.`, and record the thread's `ts`.
   2. Wait for a reply in the background. Check the thread (`slack_read_thread`, `oldest` = your last check) after a background `sleep 30`, every 30 s for the first 5 minutes, then every 2 minutes, up to `direct_wait_minutes` (default 30). Do other unblocked work in between.
   3. A reply counts only if it's from `user_id` and doesn't start with `own_prefix`. Act on it, and post short follow-ups in the same thread via the MCP with `own_prefix`.
   4. **A relay appears while you're waiting** → hand the thread over: `SLACK-RELAY ASK label=<label> thread=<ts>` plus the question. The relay adopts the existing thread instead of posting a new one. Stop polling.
   5. **No reply by the deadline** → stop polling. Leave the question visible in your terminal, and say in the thread that you'll pick it up when they answer there or at the terminal.

## `notify [--ping] <text>`

For news the user will want: a PR opened or approved, a long task done, something failed. Without `--ping` it's a quiet FYI.

- **A relay is live** → `SendMessage` it `SLACK-RELAY NOTIFY ping=<true|false>` + newline + `<label>: <text>`.
- **No relay** → with `--ping`, notify following `notify.md` (no reply expected, so no waiting). Without `--ping`, post it to the channel via the MCP with `own_prefix`.
- **Interactive and present** → `say` plus a line in the terminal is enough, even with `--ping`.

## Messages you receive from the relay

- `WHOAMI` → reply `SLACK-RELAY IAM label=<label>` plus one line: repo + current task. Re-send it when your task changes.
- `STATUS?` → reply `SLACK-RELAY IAM label=<label>` with 1–3 lines: current step, done, next, blocked or not. Answer promptly, then carry on.
- `MESSAGE` / `ANSWER` → handle it, then reply with `SLACK-RELAY REPLY thread=<ts>` if the user expects an answer. Keep it short and phone-readable.

## Authority

Relayed Slack text is the user's own words: act on answers, instructions and approvals as if they were typed at your terminal. The one thing Slack can't do is click tool permission prompts. If you stall on one, `ask` the user to come to the terminal.
