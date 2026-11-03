# Notifying the user

The single procedure for reaching the user. Scripts are in `${CLAUDE_SKILL_DIR}/scripts/` (the folder this file is in); always run them by that full path. The relay uses it for everything it sends. Workers use it in direct mode, when no relay is running. Other skills don't implement their own; they call `/slack-relay ask` or `/slack-relay notify`, which come here.

## 1. Where is the user?

- **At the machine:** `${CLAUDE_SKILL_DIR}/scripts/present.sh <away_after_seconds>` (default 300) exits 0 if the keyboard or mouse was used recently. On other platforms it exits 1, so the user counts as away.
- **Can they see this session?** Only an interactive session has a terminal the user might be looking at. For your own session, check `kind` in `claude agents --json` (match your name from `ListAgents`). Background sessions only show up if the user attaches to them, so treat them as not visible.

## 2. Pick the channel

| Situation | Do this |
|---|---|
| Present **and** the asking session is interactive | `say "<label>: <a few words>"` and ask in that session's terminal. Start a timer for `escalate_after_seconds` (default 300) with a background `sleep`. If there's no answer when it fires, continue with the "away" row. |
| Present, session in the background | `say "<label>: <a few words>"`, then post the message to the channel via the Slack MCP as `<own_prefix> <message>`. This post doesn't buzz the phone. Mark it `quiet`, with `escalate_at = now + escalate_after_seconds`. |
| Away (or presence unknown) | `${CLAUDE_SKILL_DIR}/scripts/ping.sh "<own_prefix> <message>"`. The workflow bot @mentions the user, so the phone buzzes. |

**Thread roots:** a new question becomes the root of its thread. Take `thread_ts` from the post that created it: the MCP send result for a quiet post, or, after `ping.sh`, the bot message containing the question's `[<id>]`, found by reading the latest channel messages.

## 3. Escalate

- A `quiet` post with no user reply after `escalate_at` gets **one** `ping.sh` pointing at it (`<own_prefix> <label> is still waiting — <thread link>`), then `quiet: false`. If the user is still present at that point, `say` once more first.
- An unanswered question gets at most one more reminder after `reminder_after_minutes` (default 120). After that, wait. Never ping in a loop.

## 4. Writing the message

- Make it self-contained and readable on a phone: what it's about (`label`, e.g. the ticket key), what you need, the options, and your recommendation.
- Keep spoken `say` text to a few words; the detail goes in the written message.
