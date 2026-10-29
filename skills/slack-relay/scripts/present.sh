#!/usr/bin/env bash
# Is the user at this machine? Prints seconds since the last keyboard/mouse input.
# Exit 0 = present (idle below the threshold), 1 = away or unknown (non-macOS, ioreg unavailable).
# Usage: present.sh [threshold_seconds]   (default 300)
set -uo pipefail

threshold="${1:-300}"
idle=$(ioreg -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')
[[ -n "${idle:-}" ]] || exit 1
echo "$idle"
(( idle < threshold ))
