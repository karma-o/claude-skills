---
name: ticket-autopilot
description: "Hourly autopilot that keeps the user's assigned work moving: lists their open incidents and tickets (the same list as start-of-day), skips anything already in work, and starts a background start-of-day session per item, up to a parallel limit, by priority. Use it when the user wants assigned tickets or incidents picked up automatically, says \"autopilot\", \"keep my tickets moving\" or \"work through my queue\", or asks to run start-of-day on everything assigned to them. Commands: `/ticket-autopilot boot` (start the loop), `run` (one pass now), `status`, and `--dry-run` (show what it would start). Needs the start-of-day skill; slack-relay is optional."
---

# Ticket Autopilot

Starts one `start-of-day` session per assigned incident or ticket, a few at a time, and keeps the queue moving as sessions finish implementing. All the real work (readiness check, telling the user about pickups and plans, questions, PRs, review requests) happens inside the `start-of-day` sessions. The autopilot only decides **what to start, and when**.

Arguments: `$ARGUMENTS`

- `boot` → start the autopilot loop (see **Boot**).
- `run` → do one pass now (the steps in `autopilot.md`), without starting a loop.
- `status` → show the current picture: candidates, which session owns each, whether it has a PR, free slots. Read-only.
- `--dry-run` (with `run` or `status`) → do every read, then show what a pass would start, stop or skip. Change nothing.

## Requirements

- The `start-of-day` skill with its config (`~/.claude/start-of-day/config.json`). The autopilot reuses its sources (incident system, ticket project, assignee, statuses) and its incident → ticket lookup.
- The `gh` CLI, logged in, to check for existing PRs.
- Run the autopilot from a directory the user has already trusted in an interactive `claude` session. The sessions it starts run from that same directory.
- Start the autopilot the same way the user normally starts `claude` (e.g. through their wrapper alias), so the sessions it starts inherit the same environment and credentials.
- Optional: `slack-relay`, for telling the user about problems while they're away.

## Configuration

Optional `~/.claude/ticket-autopilot/config.json`. Every key has a default:

| Key | Default | Meaning |
|---|---|---|
| `session_name` | `ticket-autopilot` | Name this session should have |
| `max_parallel` | `3` | How many items may be in the implementation phase at once |
| `interval_seconds` | `3600` | Time between passes (60–3600) |
| `waiting_after_minutes` | `30` | A pre-PR session idle this long is treated as waiting on the user and stops counting toward `max_parallel` |

## Boot

1. Check the name. If `ListAgents` shows another live session called `session_name`, stop and tell the user an autopilot is already running. If this session has a different name, ask the user once to `/rename <session_name>` (a session can't rename itself) and carry on.
2. Read `autopilot.md` (in this skill's base directory).
3. Run one pass right away.
4. Invoke the `loop` skill (Skill tool) with this plain-text prompt, not a slash command, so passes don't reload this skill: `ticket-autopilot pass: run one pass following autopilot.md (<absolute path>); Read it only if its steps are no longer in your context.`

Start it in the background, from a trusted directory:

```bash
claude --bg -n ticket-autopilot "/ticket-autopilot boot"
```

## How "in work" is decided

There's no state file. Every pass works it out from live data:

| Signal | Meaning |
|---|---|
| A live session named after the item (`<TICKET-KEY>` or `<INCIDENT-ID>`) | Someone is on it. Don't start another session. |
| An **open** PR mentioning the item's key/ID | Work is under way (by a session or by the user). Skip it. |
| Only **merged** PRs, no live session | Not proof the work is finished: there may be leftovers, or the ticket/incident may just need closing. Start a session; its readiness check works out which and asks the user. |
| A live session for the item **and** a PR | Implementation is done; the session is only watching the PR. Doesn't count toward `max_parallel`. |
| A live session for the item, no PR, idle ≥ `waiting_after_minutes` | Waiting on the user. Doesn't count toward `max_parallel`. |
| A live session for the item, no PR, busy or recently active | Implementing. Counts toward `max_parallel`. |

Messages from workers speed this up: `START-OF-DAY PR-OPEN <KEY> <URL>` and `START-OF-DAY BLOCKED <KEY> <reason>` both mean a slot may have freed up, so run a pass right away. Nothing depends on remembering them.
