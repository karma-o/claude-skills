# claude-skills

Personal Claude Code skills for daily development workflow.

## Layout

Each skill lives in its own directory under `skills/`, with a `SKILL.md` entry point and any helper files next to it:

```
skills/
├── start-of-day/
│   ├── SKILL.md
│   └── references/       # incidents.md, pr-monitoring.md, config.md
├── ticket-autopilot/
│   ├── SKILL.md
│   └── autopilot.md      # per-pass steps, read once at boot
└── slack-relay/
    ├── SKILL.md
    ├── relay.md          # per-turn relay steps, read once at boot
    └── scripts/ping.sh
```

The repo is also a Claude Code plugin marketplace (`.claude-plugin/`) offering one plugin, `dev-workflow`, that bundles all of `skills/`. See **Installation**.

## Skills

### `start-of-day`
Takes one piece of assigned work from "assigned to me" to "PR approved". Triggered by "let's start the day", `/start-of-day`, `/start-of-day <TICKET-KEY|INCIDENT-ID>`, or `--dry-run` to plan without writing anything.

**What it does:**
1. Lists your open incidents (by priority) and then your tickets, and suggests one. It skips this step when given a key.
2. For an incident: reads it, its chat thread and related PRs, then finds or creates the ticket that resolves it and moves it to in-progress.
3. Readiness check: proceeds on its own when the goal, tools and decisions are all clear; otherwise asks.
4. Finds the repo (including monorepo moves), branches after the ticket key, and commits implementation, tests and formatting separately, with a green build before pushing.
5. Opens the PR and watches it: fixes CI and review comments (human and bot), moves the ticket to review when ready, asks before posting the review request, and announces approval.
6. Reaches you where you are. If you're at the machine (keyboard/mouse idle time), it uses `say` and the terminal; otherwise it goes through `slack-relay` on Slack, with one ping when it picks something up and the plan in the same thread.

Layout: `SKILL.md` holds the workflow; `references/` holds incident handling, PR monitoring and the config keys, read only when needed.

**First-time setup:** asks for your team-specific values (ticket project and statuses, repo folders, GitHub orgs, review channel, etc.) and saves them to `~/.claude/start-of-day/config.json`. Nothing specific to you lives in the skill itself.

### `ticket-autopilot`
Keeps your assigned work moving. Run `claude --bg -n ticket-autopilot "/ticket-autopilot boot"` from a trusted directory.

**What it does:**
1. Once right away and then every hour, it builds the same list as the `start-of-day` picker: incidents first, then tickets, by priority.
2. It skips anything already in work: a live session named after the item, or a PR or branch for it.
3. It starts `claude --bg -n <KEY> "/start-of-day <KEY> --parent ticket-autopilot"` for the top items, up to 3 in the implementation phase at once.
4. Workers report "PR open" (or "blocked"), which frees their slot, and the next item starts immediately.
5. There's no state file: everything is worked out from live sessions, PRs and ticket statuses. The autopilot only messages you when something breaks; each worker tells you about its own pickup, plan and questions.

`/ticket-autopilot run --dry-run` shows what a pass would start.

### `slack-relay`
Reach you on your phone through Slack while you're away from the terminal, and route your answers back to the Claude Code sessions that asked.

**What it does:**
1. One dedicated session becomes the relay: `claude -n slack-relay "/slack-relay boot"`, or detached right away with `claude --bg -n slack-relay "/slack-relay boot"` (the fixed name lets sessions find it; name work sessions after their ticket the same way, e.g. `claude -n NRH-123`)
2. The relay asks every running session what it's working on, keeps a registry of them, and tells each session how to reach you through it, so work sessions need no extra setup, memory or CLAUDE.md
3. Worker sessions blocked on a decision send their question to the relay (`/slack-relay ask <question>`), or ping Slack directly if no relay is running
4. The relay posts each question through a Slack webhook workflow, which @mentions you, so your phone gets a push (posts made through the Slack MCP appear as you and never notify you)
5. It reads the channel and threads every ~5 min by default (configurable down to 1 min), and forwards your messages verbatim. Within 5 min of any new message from you or a session, it switches to checking every 30 s, so a live back-and-forth stays quick. Thread replies go to whoever owns the thread. New top-level messages are routed by an explicit `NRH-123: ...` / `code-b5: ...` prefix, or by matching the content against the registry; if it's unclear, the relay asks you which session you mean. Sessions reply through the relay into the same thread. You can also ask for `status`

**First-time setup:** `/slack-relay setup` asks for the channel and the webhook URL, and walks you through creating the webhook workflow in Slack Workflow Builder. Config lives in `~/.claude/slack-relay/config.json` (chmod 600, since the webhook URL is a secret).

## Installation

**As a plugin** (all skills, auto-updated from GitHub):

```
/plugin install dev-workflow --marketplace karma-o/claude-skills
```

Skills installed this way are namespaced: `/dev-workflow:start-of-day`, `/dev-workflow:slack-relay boot`, etc.

**Single skill, from a local clone** (unprefixed names, edits take effect immediately):

```bash
ln -s "$PWD/skills/slack-relay" ~/.claude/skills/slack-relay
```

Use one or the other for a given skill, not both, or it will show up twice.
