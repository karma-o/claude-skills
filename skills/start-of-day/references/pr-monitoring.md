# PR monitoring

What to do after the PR is open, until it's approved or the watch window ends.

## Set up the watch

Right after the PR is created, create two crons (CronCreate only works in the main session, not in subagents):

- **Recurring, every 10 min**: a self-contained prompt that runs the checks below for this PR (include the PR URL, ticket key and repo path).
- **One-shot expiry, `{watch_hours}` (default 2) hours after PR creation**: deletes the recurring cron (find it with CronList). GitHub's `created_at` is UTC. Convert it to `{timezone}` before adding the hours, and never use the UTC hour as the local cron hour.

## Each check

Run in parallel: CI status (`gh pr checks <n>`), reviews/approvals, and all review comments (human and bot), including which ones you already answered.

1. **Review comments**, from humans and bots alike:
   - Obvious fix → fix, commit, push, reply briefly.
   - Unclear → investigate and form an opinion; ask the user only if it's still unclear.
   - Before replying, check the thread: never post a second reply to a comment you already answered.
2. **Failing CI** → investigate, fix, commit, push.
3. **Ready for human review** (CI green **and** every comment resolved):
   1. Move the ticket to `{review_status}` (check transitions first).
   2. Delete the recurring cron.
   3. Ask the user (see **Reaching the user** in `SKILL.md`): "CI is green and all comments are resolved on <KEY>. OK to post the review request?"
   4. Only after a yes: post the review request once to `{review_channel}` using `{review_message_template}`. If the ticket asks for a different reviewing team, use `{alt_review_channel}` / `{alt_review_message_template}` instead. For multi-repo work, post **one** message listing every PR.
   5. Recreate the recurring cron to watch for approval/merge (same interval, same expiry).
4. **Approved** → tell the user (`say "PR for <KEY> has been approved"` if present; otherwise a relay `NOTIFY ping=true`).
