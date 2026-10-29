---
name: start-of-day
description: "Ticket-to-PR workflow for the user's assigned work: picks an incident or ticket (incidents first, by priority), makes sure there's a ticket for it, implements the change on a branch named after the ticket, opens a PR, and monitors it through CI and review. Use it whenever the user says \"let's start the day\", \"pick up a ticket\", \"work on <TICKET-KEY>\" or \"look at incident <ID>\", or asks to take any assigned ticket or incident into work, even if they don't name the skill. Arguments: none (show the picker), a ticket key or incident ID (skip the picker), optionally --parent <session> (report back to an orchestrator) and --dry-run (plan only, no writes). Config lives in ~/.claude/start-of-day/config.json; on first use it asks for it."
---

# Start of Day

Take one piece of assigned work from "assigned to me" to "PR approved", asking the user only when a real decision is needed.

Arguments: `$ARGUMENTS`

- *(empty)* → show the picker (step 1).
- `<TICKET-KEY>` or `<INCIDENT-ID>` → skip the picker and work on that item.
- `--parent <session>` → this session was started by an orchestrator (e.g. `ticket-autopilot`). Report to it as described in step 6. Ignore it in a dry run.
- `--dry-run` (with or without an item) → do every read step and present the plan, but don't write anything: no Jira/incident changes, no branches, commits, pushes, PRs, Slack posts or crons. Say clearly at the end that it was a dry run.

## Configuration

Read `~/.claude/start-of-day/config.json`. If it's missing or lacks a key, read `references/config.md` and run its setup. Values below in `{braces}` come from that file. Never put user-, team- or company-specific values in this skill; they belong in the config.

## Reaching the user

The user may be at the terminal or away. Decide each time you need them:

1. **At the machine?** `ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}'` gives seconds since the last keyboard/mouse input. Below `{away_after_seconds}` (default 300) → treat the user as present.
2. **Present** → announce with `say "<short text>"` and ask in the terminal.
3. **Away** → use the `slack-relay` skill's worker flow (an `ASK` or `NOTIFY` to the relay, or its direct mode if no relay is running). If that skill isn't available, ask in the terminal and wait.

When an item is **picked up while the user is away**: ping once with the item and a one-line summary, then post the plan as a reply in the same thread. If the plan has no open questions, carry on without waiting. If it has questions, ask them there and work on anything not blocked by them meanwhile.

## Step 1 — Pick the work

Skip if an item was given as an argument.

1. Fetch in parallel:
   - **Incidents** assigned to `{incident_assignee}` that aren't resolved or closed, using the incident tool in `{incident_source}` (see `references/incidents.md`).
   - **Tickets** from `{jira_project_key}` assigned to `{jira_assignee}` with status in `{pick_statuses}`.
2. Order: incidents first by priority (P1 → P4), then tickets by priority, then oldest first.
3. Show one numbered list (`ID — title — priority — status`) and ask which one to take. Recommend the top item.

## Step 2 — Make sure there's a ticket

- **Ticket** → fetch it: description, comments, linked issues, attachments.
- **Incident** → follow `references/incidents.md`. It finds or creates the ticket that resolves the incident and moves it to in-progress. From here on, the **ticket key** is the work item's key (branch, commits, PR title).

## Step 3 — Readiness check

Decide whether you can finish this without the user. Proceed on your own only if all of these hold:

- the goal and acceptance criteria are clear from the ticket, incident and comments;
- you have the tools and access it needs (repos, environments, credentials, MCPs);
- no decision is left open (design choices, scope, which team owns it);
- it isn't already done: if merged PRs exist for this item, check what they covered. If nothing is left, the plan is to verify and then propose the status update or closure to the user (don't change incident state yourself).
- nothing irreversible or outward-facing is involved beyond the normal branch → PR flow.

Then present a short plan (what, where, how you'll verify) and proceed without waiting. If anything fails the check, ask the specific questions (see **Reaching the user**). Don't guess on open decisions. Infra, config and communication changes usually fail the "no open decision" test; say why when you flag them.

## Step 4 — Repository setup

1. Search each of `{repos_roots}` for the repo, `{repos_search_depth}` levels deep (default 4), because repos are often grouped in sub-folders: `find <root> -maxdepth <depth> -name .git -prune 2>/dev/null | sed 's#/\.git$##'`. Match the directory name case-insensitively, or the `origin` URL for repos renamed on the server. If several clones match, use the one whose `origin` is the live (non-archived) repo and mention the duplicates to the user. Check whether it has been moved into a monorepo: a repo with a README or redirect saying so, or a directory of that name inside a bigger repo.
2. Not found locally → search `{github_orgs}`. Use the `gh` CLI if the GitHub MCP can't see an org.
3. Needs cloning → clone it yourself over SSH (`git clone git@github.com:<org>/<repo>.git`) into `{clone_root}` (default: the first of `{repos_roots}`), keeping any sub-folder layout the user already uses for related repos. In a dry run, only show the command.
4. Before branching: confirm `origin` points at the expected remote, then `git checkout <default branch> && git pull`.
5. If the change spans several repos, repeat for each one; they all use the same branch name.

## Step 5 — Implement

- Branch named exactly after the ticket key (e.g. `ABC-123`).
- Commit in this order, as separate commits: implementation, tests, formatting/style.
- Run `{build_command}` (use the repo's own build if it differs) and make sure it passes before pushing.
- Stage files explicitly; never `git add -A` or `git add .`. Never commit secrets, `.env` files or logs.

## Step 6 — Push and open the PR

- Push the branch and open the PR without asking. Title: `{pr_title_format}`.
- Don't move the ticket to the review status yet; step 7 does that once the PR is ready.
- Tell the user the PR is open (see **Reaching the user**).
- If started with `--parent <session>`: `SendMessage` that session `START-OF-DAY PR-OPEN <KEY> <PR_URL>`. That tells it implementation is done and this session is only watching the PR now. If you stop early instead (blocked, or the readiness check sent questions that went unanswered), send `START-OF-DAY BLOCKED <KEY> <one-line reason>`.

## Step 7 — Monitor the PR

Follow `references/pr-monitoring.md`: CI and review comments are handled on your own, the ticket moves to `{review_status}` when ready, the review request is posted only after the user agrees, and the user is told when the PR is approved.
