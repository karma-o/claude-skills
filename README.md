# claude-skills

Personal Claude Code skills for daily development workflow.

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

## Installation

Add this repo as a Claude Code skill source in your `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "personal-skills": {
      "source": "git",
      "url": "git@github-personal:karma-o/claude-skills.git"
    }
  }
}
```

Then install via `/marketplace` or by enabling it in Claude Code settings.
