# Slack Relay: setup

Run when `config.json` is missing or the user asks for `setup`. The config format is in `SKILL.md` next to this file.

1. Check the prerequisites:
   - **Slack MCP.** The skill needs the official Slack MCP (`slack_read_channel`, `slack_read_thread`, `slack_send_message`, `slack_add_reaction`). If those tools aren't available, tell the user to install the `slack` plugin from the official marketplace (`/plugin install slack@claude-plugins-official`), restart Claude Code and authenticate.
   - **Channel.** The Slack MCP can't create channels, so the user creates one in Slack: a private channel with only themselves in it works best. Look its ID up with `slack_search_channels` (`channel_types: private_channel`) and confirm it, or ask for the ID (channel details → About).
2. Ask the user for: webhook URL, payload field name (default `message`). Take `user_id` from the Slack MCP tool descriptions ("Current logged in user's user_id is ..."); confirm it.
3. If they don't have a webhook workflow yet, walk them through it:
   - Slack → Workflow Builder → New workflow → trigger **From a webhook**, add a text variable (e.g. `message`).
   - Step **Send a message to a channel** → the relay channel, text: `@<user> {message}`.
   - Publish (suggest making the workflow private first) and copy the `https://hooks.slack.com/triggers/...` URL.
4. Write the config with `umask 077`, then `chmod 600` it (`umask` doesn't tighten a file that already exists when setup is rerun). Then send a test with `scripts/ping.sh "<own_prefix> slack-relay test ping, reply in the thread"` and confirm with the user that the phone buzzed and that you can read their thread reply.
5. Suggest the user add shortcuts to `~/.zshrc` for convenience (`slack-relay-stop` uses zsh-only syntax, so it won't work in bash):
   ```zsh
   # Start the slack-relay Claude Code session in the background (run from a trusted dir)
   alias slack-relay='claude --bg -n slack-relay "/slack-relay boot"'
   
   # Stop the slack-relay session. With --workers, also stop idle ticket/incident sessions.
   slack-relay-stop() {
   local agents
   agents=$(claude agents --json 2>/dev/null) || return
   local -a targets=(slack-relay)
   [[ "$1" == "--workers" ]] && targets+=( ${(f)"$(jq -r '.[] | select(.status=="idle" and (.name|test("^([A-Z][A-Z0-9]+-[0-9]+|INC[0-9]+)$"))) | .name' <<<"$agents")"} )
   local name id
   for name in $targets; do
   id=$(jq -r --arg n "$name" '.[] | select(.name==$n) | .sessionId[:8]' <<<"$agents" | head -1)
   if [[ -n "$id" ]]; then claude stop "$id" >/dev/null && echo "stopped $name"; else echo "$name not running"; fi
   done
   }
   ```
6. Offer permission rules for the relay. The skill pre-approves its tools only for the turn that invokes it, and every relay tick after `boot` is a new turn, so a `--bg` relay would otherwise stop at a permission prompt nobody sees. Show the user these rules (with `<dir>` = the absolute `${CLAUDE_SKILL_DIR}`), and only if they agree, add them to `permissions.allow` in `~/.claude/settings.json`, keeping what's already there:
   ```json
   "mcp__plugin_slack_slack__slack_read_channel",
   "mcp__plugin_slack_slack__slack_read_thread",
   "mcp__plugin_slack_slack__slack_send_message",
   "mcp__plugin_slack_slack__slack_add_reaction",
   "Bash(<dir>/scripts/ping.sh *)",
   "Bash(<dir>/scripts/present.sh *)",
   "Bash(<dir>/scripts/state.sh *)",
   "Bash(jq *)", "Bash(sleep *)", "Bash(say *)", "Bash(claude agents *)"
   ```
   If their Slack tools have a different prefix (check the tool names), adjust the `mcp__…` rules. The plugin directory changes when the plugin updates, so rerun this step after an update.
7. Inform the user of the polling intervals: `idle_poll_seconds` (default 270, min 60) and `hot_poll_seconds` (default 30, used within 5 min of any activity). Ask if they would like to tweak them. Closing the laptop pauses everything.
