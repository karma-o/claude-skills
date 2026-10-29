# Ticket Autopilot: one pass

Steps for one pass. `boot` reads this file once; each loop wake-up then runs these steps from context. Re-read this file only if its steps are no longer in your context. The rules for deciding what's "in work" are in `SKILL.md` next to this file.

Keep passes small. This session runs all day, and everything a pass reads stays in context. Use compact output (`--json` with `jq` filters, concise MCP formats), and say nothing on a pass that changes nothing.

## Steps

1. **Candidates.** Using the `start-of-day` config, list the open incidents assigned to the user and the tickets in its project with status in `pick_statuses`, exactly as its picker does (`references/incidents.md` in that skill describes listing incidents). Order: incidents by priority, then tickets by priority, then oldest first.

2. **Resolve incidents to tickets.** For each incident, look for the ticket that resolves it (same search as `start-of-day`'s incident flow). If one exists, the item is that ticket **and** the incident: drop the ticket from the list if it's there separately, and use both IDs in the checks below. If none exists, the item is the incident alone; its session will create the ticket.

3. **Sessions.** `claude agents --json` → live sessions (`name`, `status`, `pid`). Match them to items by name: the ticket key or the incident ID. For how long a session has been idle, read `statusUpdatedAt` (epoch ms) from `~/.claude/sessions/<pid>.json`. If that's unavailable, treat any idle pre-PR session as waiting on the user.

4. **PRs and branches.** For each item's ticket key, look for open or merged PRs and branches mentioning it across the `start-of-day` `github_orgs` (e.g. `gh search prs "<KEY>" --owner <org> --json url,state,title`). Batch per org where possible.

5. **Classify each item** using the table in `SKILL.md`: skip / watching the PR / waiting on the user / implementing / free to start.

6. **Start new sessions.** Free slots = `max_parallel` − implementing count. For the top free-to-start items, up to that many, from this session's working directory:
   ```bash
   claude --bg -n <ID> "/start-of-day <ID> --parent <this session's name>"
   ```
   `<ID>` is the ticket key, or the incident ID if no ticket exists yet. Check the output for the `backgrounded` line. If it fails (e.g. "Workspace not trusted"), report it (step 8) and don't retry this pass.

7. **Worker messages.** On `START-OF-DAY PR-OPEN` or `BLOCKED` from a worker, run steps 1–6 again right away; that's how a freed slot gets reused without waiting for the next hourly pass. Nothing else is needed for them.

8. **Report problems only.** Starting sessions needs no message: each `start-of-day` session tells the user about its own pickup and plan. Tell the user only about problems that stop the autopilot from working: a failed session start, an MCP/CLI auth error, a config file that's missing or broken. Use `slack-relay` (`NOTIFY ping=true`) if a relay is running, otherwise `say` plus a terminal message. Report each distinct problem once, not on every pass while it lasts.

9. **Schedule.** `ScheduleWakeup` with the same plain-text prompt the loop was started with and `delaySeconds: <interval_seconds>`. Mark `noop: true` if the pass started nothing and found no new problems.

## Dry run

With `--dry-run`, do steps 1–5, then print one line per item, `ID — title — priority — decision — why`, plus the free slot count and what step 6 would start. Start nothing and send nothing.
