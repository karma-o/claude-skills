# Configuration

`~/.claude/start-of-day/config.json` holds everything specific to the user, team or company. The skill itself stays generic. A file (instead of memory) means the config works from any directory and in background sessions.

## Setup

If the file is missing, or a required key is missing, ask the user for the missing values (one message, all questions at once). If you already know some values from memory or earlier conversation, offer them as defaults. Write the file with `umask 077`.

| Key | Required | Meaning | Example |
|---|---|---|---|
| `jira_project_key` | yes | Project to pick tickets from and to create incident tickets in | `ABC` |
| `jira_assignee` | yes | Assignee name/ID as the ticketing tool expects it | `Jane Smith` |
| `pick_statuses` | yes | Ticket statuses shown in the picker | `["To Do", "In Progress"]` |
| `in_progress_status` | yes | Status to move a ticket to when work starts | `In Progress` |
| `review_status` | yes | Status once the PR is ready for review | `Verify` |
| `incident_source` | no | Incident system, or `none` | `servicenow` |
| `incident_assignee` | if incidents | Assignee as the incident tool expects it | `jane.smith@example.com` |
| `incidents_ticket_project` | no | Project for incident tickets, if not `jira_project_key` | `ABC` |
| `incident_ticket_type` | no | Issue type for incident tickets | `Bug` |
| `incident_ticket_defaults` | no | Extra fields for incident tickets (labels, components) | `{"labels": ["incident"]}` |
| `repos_roots` | yes | Local folders that hold repos | `["~/code/work"]` |
| `repos_search_depth` | no | How many folder levels below each root to search for repos (default 4) | `4` |
| `clone_root` | no | Where to clone repos that aren't local yet (default: first of `repos_roots`) | `~/code/work` |
| `github_orgs` | yes | GitHub orgs to search for repos/PRs | `["my-org", "my-org-sandbox"]` |
| `build_command` | yes | Default build/verify command | `./gradlew build` |
| `pr_title_format` | yes | PR title pattern | `{KEY}: {short description}` |
| `review_channel` | no | Chat channel ID for review requests | `C0123456789` |
| `review_message_template` | no | Review request text (`{PR_URL}`, `{KEY}`, `{PR_TITLE}`) | `<!subteam^S0123> please have a look at *<{PR_URL}\|{KEY}: {PR_TITLE}>*` |
| `alt_review_channel` / `alt_review_message_template` | no | Used when a ticket asks for another team's review | |
| `timezone` | yes | For cron times | `Europe/Berlin` |
| `watch_hours` | no | How long to monitor a PR (default 2) | `2` |
| `away_after_seconds` | no | Idle seconds after which the user counts as away (default 300) | `300` |
