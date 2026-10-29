# claude-skills

Personal Claude Code skills for daily development workflow.

## Layout

Each skill lives in its own directory under `skills/`, with a `SKILL.md` entry point and any helper files next to it:

```
skills/
├── start-of-day/
│   └── SKILL.md
└── slack-relay/
    ├── SKILL.md
    └── scripts/ping.sh
```

The repo is also a Claude Code plugin marketplace (`.claude-plugin/`) offering one plugin, `dev-workflow`, that bundles all of `skills/`. See **Installation**.

## Skills

### `start-of-day`
A full ticket-to-PR workflow triggered by saying "let's start the day" or `/start-of-day`.

**What it does:**
1. Fetches your In Progress Jira tickets and asks which to work on
2. Analyzes the ticket and implements autonomously (code-only) or asks for input (infra/config)
3. Finds or clones the repo, creates a branch, commits implementation + tests + formatting
4. Opens a PR and moves the Jira ticket to Verify
5. Monitors the PR for 2 hours — fixes CI failures and review comments autonomously, asks for your approval before posting a Slack review request

**First-time setup:** On first use, you'll be asked for your team-specific config (Jira board URL, GitHub org, Slack channel, timezone, etc.). Answers are saved to memory and reused in future sessions — you won't be asked again.

### `slack-relay`
Reach you on your phone through Slack while you're away from the terminal, and route your answers back to the Claude Code sessions that asked.

**What it does:**
1. One dedicated session becomes the relay: `claude -n slack-relay "/slack-relay boot"` (the fixed name lets sessions find it; name work sessions after their ticket the same way, e.g. `claude -n NRH-123`)
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
