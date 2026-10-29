---
name: start-of-day
description: "Full ticket-to-PR workflow: pick a Jira ticket, implement it, open a PR, and monitor it through review. On first use, prompts for team-specific config (Jira board, GitHub org, Slack channel, etc.) and saves it to memory for future sessions."
---

# Start of Day Workflow

A guided workflow for picking up a Jira ticket, implementing it, opening a PR, and monitoring it through review.

## Configuration

On first use, if `skill_config_start_of_day` is not found in memory, ask the user for each value below and save them to memory as `skill_config_start_of_day`:

| Key | Question to ask |
|---|---|
| `jira_board_url` | What is your Jira board URL? (e.g. `https://jira.example.com/secure/RapidBoard.jspa?rapidView=12345`) |
| `jira_project_key` | What is your Jira project key? (e.g. `NRH`) |
| `jira_assignee_name` | What is your display name in Jira? (e.g. `Jane Smith`) |
| `github_org` | What is your GitHub org or username for work repos? (e.g. `my-org`) |
| `repos_root` | Where do your local repos live? (e.g. `~/Code/Work/`) |
| `slack_review_channel_id` | What is the Slack channel ID for PR review requests? |
| `slack_review_group_id` | What is the Slack user group ID to tag for reviews? (e.g. `S0123456789`) |
| `user_email` | What is your work email address? |
| `timezone` | What is your local timezone? (e.g. `Europe/Warsaw`) |
| `build_command` | What is the build command for your projects? (e.g. `./gradlew build -x spotlessJava`) |
| `test_command` | What is the test command? (e.g. `./gradlew test -x spotlessJava`) |

Once all values are collected, save them and proceed without asking again in future sessions.

---

## Step 1 — Ticket selection

- Fetch tickets from the Jira board at `{jira_board_url}` assigned to `{jira_assignee_name}` with status **In Progress**
- List them and ask: "Which ticket do you want to work on today?"
- Wait for the user to pick one, then proceed

## Step 2 — Ticket analysis

- Fetch the full ticket: description, comments, linked issues
- Classify the work:
  - **Code-only** → proceed autonomously: analyze, plan, implement without asking
  - **Infra / config / communication** → flag explicitly, require user input before proceeding
- For code-only: briefly present the plan, then proceed immediately without waiting for approval
- Only pause when genuinely blocked or the change is irreversible and ambiguous

## Step 3 — Repository setup

- Search locally under `{repos_root}` first
- If not found: search `https://github.com/{github_org}`
- If repo needs cloning: suggest the SSH clone command to the user — never run `git clone` yourself

## Step 4 — Implementation

Before creating the branch:
```
git checkout main && git pull origin main
```
Then create a branch named exactly after the ticket key (e.g. `NRH-1234`).

Commit in this order, each as a separate commit:
1. Implementation
2. Tests
3. Formatting / style (run `{build_command}` to verify it passes)

Build must pass before pushing.

## Step 5 — Push & Jira update

- Push branch and open PR — no approval needed
- Check available Jira transitions, then move ticket to the equivalent of **Verify** status

## Step 6 — PR monitoring (2 hours)

Immediately after the PR is created, set up two crons (CronCreate is only available in the main session):

**Recurring 10-min cron** — prompt should:
1. Check in parallel: review comments, CI status (`gh pr checks {PR_NUMBER}`), reviews/approvals
2. **Unresolved review comments** → obvious fix: fix, commit, push; ambiguous: investigate first, ask user only if truly stuck
3. **Failing CI** → investigate, fix, commit, push autonomously
4. **All CI green AND all comments resolved** → ask the user: "CI is green and all comments are resolved on {TICKET_KEY} — ok to post the Slack review request?"
   → Only after user says yes: post once to `{slack_review_channel_id}`:
   `<!subteam^{slack_review_group_id}> please have a look at *<{PR_URL}|{TICKET_KEY}: {PR_TITLE}>*`
5. **PR approved** → run: `say "PR for {TICKET_KEY} has been approved"`

**One-shot expiry cron** — fires 2 hours after PR creation:
- GitHub `created_at` is UTC. Convert to local time using `{timezone}` offset, then add 2 hours to get the cron time.
- Example (Warsaw CEST = UTC+2): `created_at=17:28Z` → local 19:28 → expiry 21:28 → cron `28 21 13 8 *`
- Never use the UTC hour directly as the local cron hour.
- When it fires: use CronList to find the recurring cron, then CronDelete it.
