#!/usr/bin/env bash
# Posts a message through the Slack webhook workflow, which @mentions the user so their phone gets a push.
# Usage: ping.sh "<message>"
set -euo pipefail

config="${SLACK_RELAY_CONFIG:-$HOME/.claude/slack-relay/config.json}"
[[ $# -eq 1 && -n "$1" ]] || { echo "usage: $0 <message>" >&2; exit 2; }
[[ -r "$config" ]] || { echo "config not found: $config (run /slack-relay setup)" >&2; exit 1; }

url=$(jq -er '.webhook_url' "$config")
field=$(jq -r '.webhook_message_field // "message"' "$config")

jq -n --arg f "$field" --arg m "$1" '{($f): $m}' \
  | curl -sS --fail-with-body -X POST "$url" -H 'Content-Type: application/json' --data-binary @-
echo
