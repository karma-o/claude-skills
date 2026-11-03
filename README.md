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
    ├── notify.md         # how the user is reached: say, quiet post, phone ping, escalation
    ├── worker.md         # ask / notify for any session, with or without a relay
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
6. Reaches you through `slack-relay` (`ask` / `notify`): `say` when you're at the machine, Slack or a phone ping when you're not, with one message when it picks something up.

Layout: `SKILL.md` holds the workflow; `references/` holds incident handling, PR monitoring and the config keys, read only when needed.

**First-time setup:** asks for your team-specific values (ticket project and statuses, repo folders, GitHub orgs, review channel, etc.) and saves them to `~/.claude/start-of-day/config.json`. Nothing specific to you lives in the skill itself.

### `ticket-autopilot`
Keeps your assigned work moving. Run `claude --bg -n ticket-autopilot "/ticket-autopilot boot"` from a trusted directory.

**What it does:**
1. Once right away and then every hour, it builds the same list as the `start-of-day` picker: incidents first, then tickets, by priority.
2. It skips anything already in work: a live session named after the item, or an open PR for it. Merged PRs don't count as done; the session checks whether anything is left or whether the item just needs closing.
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
5. Any session reaches you with `/slack-relay ask <question>` or `/slack-relay notify [--ping] <text>`, whether or not a relay is running. With a relay, the relay tracks the thread. Without one, the session posts to Slack itself and checks for your reply for a while. How you're told depends on where you are: `say` (plus the terminal for interactive sessions) if you're at the machine, a quiet post that escalates to a phone ping if you don't answer, or a phone ping straight away if you're away. All of this lives in `notify.md`.
6. It reads the channel and threads every ~5 min by default (configurable down to 1 min), and forwards your messages verbatim. Within 5 min of any new message from you or a session, it switches to checking every 30 s, so a live back-and-forth stays quick. Thread replies go to whoever owns the thread. New top-level messages are routed by an explicit `NRH-123: ...` / `code-b5: ...` prefix, or by matching the content against the registry; if it's unclear, the relay asks you which session you mean. Sessions reply through the relay into the same thread. You can also ask for `status`; it flags sessions that look stuck on a permission prompt, so you know which one to `claude attach` to

**First-time setup:** create the relay channel in Slack first (a private one with only you in it; the Slack MCP can't create channels). Then `/slack-relay setup` finds the channel, asks for the webhook URL, walks you through creating the webhook workflow in Slack Workflow Builder, suggests `~/.zshrc` shortcuts to start and stop the relay, and offers permission rules so a background relay doesn't stop at a prompt nobody sees. Config lives in `~/.claude/slack-relay/config.json` (chmod 600, since the webhook URL is a secret).

**Running the relay:**

Start it detached, with no terminal to keep open (a Claude Code background session; the `-n` name is kept):

```bash
claude --bg -n slack-relay "/slack-relay boot"
```

Or in a dedicated terminal: `claude -n slack-relay --model sonnet "/slack-relay boot"`.

- Manage it with `claude agents` (list), `claude attach <id>` (open it, e.g. to `/rename` or answer a permission prompt), `claude logs <id>` and `claude stop <id>`.
- Run it from a directory you've already trusted in an interactive `claude` session, otherwise it exits with "Workspace not trusted".
- Routing free-form messages to the right session needs judgment, so use a capable model. `sonnet` is a good default; drop `--model` to use your default (e.g. Opus); `haiku` is fine if you always address sessions explicitly (`NRH-123: ...`). Inside a running session, `/model` switches it.
- It polls every `idle_poll_seconds` (default 270, about 4.5 min) when idle and every `hot_poll_seconds` (default 30) within 5 minutes of any activity. Both are in the config.
- It works only while the machine is awake. A relay started in a terminal also stops when you close that terminal; a `--bg` relay doesn't need one. Closing the laptop pauses everything; on wake the loop continues and catches up on the channel.
- To stop it: interrupt the loop in its terminal, or `claude stop <id>` (or `slack-relay-stop`) for a background one.

**Session names:**

Sessions address each other by name (`ListAgents` shows it, `SendMessage` uses it). A session gets its name in one of three ways (`nameSource` in `~/.claude/sessions/<pid>.json`):

| Source | Example | When |
|---|---|---|
| `derived` | `code-89` | default for interactive sessions: cwd folder name + 2 characters of the session id |
| `auto` | `slack-relay-status-tick` | background sessions get a title generated from their task |
| set by you | `slack-relay`, `NRH-123` | `claude -n <name>` at start, `/rename <name>` in the session, or `Ctrl+R` in the session picker |

- A session can't rename itself, so the skill can only ask you for a name.
- Keep the relay called `slack-relay` (`relay_name` in the config), so sessions can find it and its name survives restarts. It refuses to boot if another live session already has that name.
- Name work sessions after their ticket (`claude -n NRH-123`), so `NRH-123: ...` in Slack reaches them directly.
- Starting new sessions from Slack isn't a supported command, but the relay is a full Claude Code session, so you can ask it to start one (for example in a repo you've already trusted) and it may well do it.

**Design notes:**
- The webhook could DM you each message instead of posting to a channel, which would feel more like a real conversation and notify on every message. But DMs from a workflow can't use threads, and threads are what keep each session's conversation separate, so the channel is the compromise.
- The relay could be lighter on context by moving more of the routing and thread tracking into scripts and state files, so the relay session has less to work out by thinking.

## Installation

**As a plugin** (all skills):

```
/plugin install dev-workflow --marketplace karma-o/claude-skills
```

Skills installed this way also get a namespaced form (`/dev-workflow:start-of-day`, `/dev-workflow:slack-relay boot`); the bare names work too unless another skill has the same name.

The plugin has no `version`, so every commit pushed to `main` is a new version. Third-party marketplaces don't auto-update by default: turn it on in `/plugin` → Marketplaces → `personal-skills` → Enable auto-update (it then pulls at startup), or update by hand with `claude plugin marketplace update personal-skills && claude plugin update dev-workflow@personal-skills` and restart.

**Single skill, from a local clone** (unprefixed names, edits take effect immediately):

```bash
ln -s "$PWD/skills/slack-relay" ~/.claude/skills/slack-relay
```

Use one or the other for a given skill, not both, or it will show up twice.
