#!/usr/bin/env bash
# Applies a jq filter to the relay's state.json in place (atomic write; creates {} if missing).
# One script, so one pre-approved command covers every state update.
# Usage: state.sh [jq options] '<filter>'    e.g. state.sh --arg ts "$ts" '.channel_cursor = $ts'
set -euo pipefail

state="${SLACK_RELAY_STATE:-$HOME/.claude/slack-relay/state.json}"
[[ $# -ge 1 ]] || { echo "usage: $0 [jq options] '<filter>'" >&2; exit 2; }

umask 077
mkdir -p "$(dirname "$state")"
[[ -s "$state" ]] || echo '{}' > "$state"

tmp=$(mktemp "$state.XXXXXX")
trap 'rm -f "$tmp"' EXIT
jq "$@" "$state" > "$tmp"
mv "$tmp" "$state"
