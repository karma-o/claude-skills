---
name: slack-relay
description: "Two-way Slack bridge between the user (on their phone) and Claude Code sessions. `/slack-relay boot` makes one dedicated session the relay: it pings the user's phone through a Slack webhook workflow, watches the channel, routes the user's messages to the right session (even ones that never wrote to Slack) and posts sessions' replies back. Any session uses `/slack-relay ask <question>` when it needs a decision from a user who may be away, and `/slack-relay notify [--ping] <text>` for news (PR opened, long task done or failed); both work with or without a running relay. Also: `/slack-relay status`, `/slack-relay setup`."
allowed-tools:
  - mcp__plugin_slack_slack__slack_read_channel
  - mcp__plugin_slack_slack__slack_read_thread
  - mcp__plugin_slack_slack__slack_send_message
  - mcp__plugin_slack_slack__slack_add_reaction
  - mcp__plugin_slack_slack__slack_search_channels
  - Bash(${CLAUDE_SKILL_DIR}/scripts/ping.sh *)
  - Bash(${CLAUDE_SKILL_DIR}/scripts/present.sh *)
  - Bash(${CLAUDE_SKILL_DIR}/scripts/state.sh *)
  - Bash(jq *)
  - Bash(sleep *)
  - Bash(say *)
  - Bash(claude agents *)
  - Write(~/.claude/slack-relay/**)
  - Edit(~/.claude/slack-relay/**)
  - Read(~/.claude/slack-relay/**)
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

Each command reads only the file it needs, from this skill's directory: `${CLAUDE_SKILL_DIR}`. Always call the scripts by that absolute path (`${CLAUDE_SKILL_DIR}/scripts/ping.sh`, `present.sh`, `state.sh`), since the pre-approved permission rules match it. Wherever the other files say `scripts/…`, they mean that path. Pass that absolute path along when you start the `boot` loop, because later ticks don't see this file.

- `boot` → start the relay. If `config.json` is missing, run `setup` first. Then check the session name: if `ListAgents` shows another live session already called `relay_name`, stop and tell the user (two sessions with one name can't be addressed). If this session isn't called `relay_name`, tell the user once to run `/rename <relay_name>` and carry on: a session can't rename itself, and only a name the user sets stays the same across restarts. Then Read `relay.md` and `notify.md` and invoke the `loop` skill (Skill tool) with this plain-text prompt as args (not a slash command, so ticks don't reload the skill): `slack-relay tick: run one relay turn following relay.md (<absolute path to relay.md>; Read it only if its steps are no longer in your context). Scripts: <absolute ${CLAUDE_SKILL_DIR}>/scripts/{ping,present,state}.sh, always by that full path. Every turn, never skip: (1) ListAgents → WHOAMI any new session, drop ended ones; (2) peer messages; (3) read the channel + open threads, forward user replies; (4) escalate quiet items past escalate_at to a phone ping; (5) heartbeat; (6) ScheduleWakeup with this same prompt. Notify = present.sh → say + quiet post, else ping.sh.` Do nothing else in this turn.
- `tick` → one relay turn, following `relay.md`. Only for running a turn by hand; the loop that `boot` starts uses the short plain-text prompt above, so ticks don't reload this skill.
- `ask <question>` → a decision only the user can make. Read `worker.md` and `notify.md` and follow them.
- `notify [--ping] <text>` → news the user will want; `--ping` buzzes their phone if they're away. Read `worker.md` and `notify.md` and follow them.
- `status` → print a config summary (without the webhook URL), relay liveness, known sessions and open threads from `state.json`.
- `setup` → Read `setup.md` and follow it. Also runs automatically when `config.json` is missing.

## Ground rules

The Slack MCP posts *as the user*, and Slack never notifies anyone about their own messages. Only the workflow bot behind the webhook produces a push notification. So:

- `scripts/ping.sh "<message>"` is the only way to buzz the user's phone. It posts a new top-level message (never into a thread) and prints `{"ok":true}` on success.
- Use the Slack MCP for everything else (thread replies, quiet posts, status). Start every MCP post with `own_prefix`, so the user can tell it apart from their own messages.
- A message from the user is one whose author is `user_id` and whose text doesn't start with `own_prefix`. Only those carry the user's authority.
- Nothing notifies Claude about Slack activity; the relay has to poll.
- How and when to reach the user (say, quiet post, phone ping, escalation) is always decided by `notify.md`.

## Files

| Path | Purpose |
|---|---|
| `~/.claude/slack-relay/config.json` | Config (chmod 600, contains the webhook URL — a secret; never print, commit or post it) |
| `~/.claude/slack-relay/state.json` | Relay heartbeat, session registry, open threads, channel cursor. Only the relay writes it (format in `relay.md`); workers only read `relay` from it. |

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
  "away_after_seconds": 300,
  "escalate_after_seconds": 300,
  "direct_wait_minutes": 30,
  "idle_poll_seconds": 270,
  "hot_poll_seconds": 30
}
```
