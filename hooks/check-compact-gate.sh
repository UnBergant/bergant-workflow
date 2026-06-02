#!/bin/bash
# PreToolUse(Agent) hook: blocks Agent tool calls when awaitingCompact is set.
# Part of lifecycle system: skill=~/.claude/skills/lifecycle/SKILL.md
#
# The lifecycle sets awaitingCompact:true at two points:
# 1. After `start` — blocks until /compact before SCOPE/PLAN begins
# 2. After PLAN completes — blocks until /compact before IMPLEMENT begins
# The SessionStart(compact) hook (inject-lifecycle-state.sh) clears the flag.
#
# Exit codes:
#   0 — allow (no flag, or no lifecycle active)
#   2 — block (compact required, stderr message sent to Claude)

STATE_FILE=".lifecycle-state.json"

# No lifecycle active → allow
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

AWAITING=$(jq -r '.awaitingCompact // false' "$STATE_FILE" 2>/dev/null)

if [ "$AWAITING" = "true" ]; then
  CURRENT_STEP=$(jq -r '.currentStep // "unknown"' "$STATE_FILE" 2>/dev/null)
  echo "COMPACT REQUIRED: Context should be compressed before $CURRENT_STEP begins. Ask the user to run /compact first. Do NOT proceed until compact is done." >&2
  exit 2
fi

exit 0
