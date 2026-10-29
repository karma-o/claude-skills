# Incidents

How to turn an assigned incident into a ticket you can work on. Read this when the work item is an incident, or when listing incidents in the picker.

## Listing incidents (picker)

Use the incident tool for `{incident_source}` (e.g. a ServiceNow MCP's list/search incidents) with: assigned to `{incident_assignee}`, state not resolved/closed/cancelled. Show number, short description, priority and state. Sort by priority (1 = highest), then by opened date.

## Understanding the incident

Fetch, in parallel where possible:

1. The incident itself: description, priority, affected service, assignment group, all comments and work notes, attachments.
2. Any chat thread linked from it (e.g. a Slack permalink in the description or comments). Read the thread.
3. Related code changes: search PRs and branches in `{github_orgs}` that mention the incident ID, and PRs linked from the comments. Note what they already fixed.

## Find or create the ticket

The fix is tracked as a ticket in `{jira_project_key}` (`{incidents_ticket_project}` if set).

1. **Search first.** Look for an existing ticket that resolves this incident: the incident ID in the summary, description, comments or remote links, plus tickets linked from the incident. Check open and recently closed ones.
2. **Found** → use it. If it's in a not-started status, move it to `{in_progress_status}`.
3. **Not found** (and not a dry run) → create one:
   - Type `{incident_ticket_type}` (default: Bug), summary `<INCIDENT-ID>: <short description>`.
   - Description: a link to the incident, a summary of what's known, and related PRs.
   - Add any labels/components from `{incident_ticket_defaults}`.
   - Assign it to `{jira_assignee}`. **Assignment can fail through the ticketing MCP.** If it does, say so in your status message and give the user the ticket link to assign it by hand. Don't retry in a loop.
   - Move it to `{in_progress_status}` (check the available transitions first).
4. Mention the ticket key in your summary so the user can see the incident → ticket link. Don't post to the incident (comments or work notes) unless the user asks; those are visible to other teams.

From here on, use the **ticket key** for the branch, commits and PR title. Put the incident ID in the PR description.
