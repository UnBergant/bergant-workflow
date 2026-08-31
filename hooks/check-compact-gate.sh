#!/bin/bash
# PreToolUse(Agent) hook: blocks Agent tool calls when awaitingCompact is set.
# Part of lifecycle system: skill=skills/lifecycle/SKILL.md (bergant-workflow plugin)
#
# The lifecycle sets awaitingCompact:true at two points:
# 1. After `start` — blocks until /compact before SCOPE/PLAN begins
# 2. After PLAN completes — blocks until /compact before IMPLEMENT begins
# The SessionStart(compact) hook (inject-lifecycle-state.sh) clears the flag.
#
# It matches agent launches AND the edit tools. Agent launches alone left an obvious way
# through: the main session could simply write the code itself and never spawn anything, which
# is exactly the context this gate exists to protect — subagents have their own. Bash is
# deliberately NOT matched: reading logs, running tests and checking git status while deciding
# whether to compact is not the thing being gated.
#
# The block is meant to be skippable on purpose, not to be argued with:
# `/bergant-workflow:lifecycle skip-compact` clears the flag and records that the user chose to.
#
# Exit codes:
#   0 — allow (no flag, or no lifecycle active)
#   2 — block (compact required, stderr message sent to Claude)

# shellcheck source=lib-state.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-state.sh"

STATE_FILE="$(find_state_file)" || exit 0

AWAITING=$(jq -r '.awaitingCompact // false' "$STATE_FILE" 2>/dev/null)

if [ "$AWAITING" = "true" ]; then
  CURRENT_STEP=$(jq -r '.currentStep // "unknown"' "$STATE_FILE" 2>/dev/null)
  MSG="COMPACT REQUIRED: Context should be compressed before $CURRENT_STEP begins. Ask the user to run /compact. If they would rather continue without compacting, they can run /bergant-workflow:lifecycle skip-compact — that is their call to make, not yours. Do NOT proceed until one of the two has happened."

  # Piggyback the version check on the block that already opens every lifecycle.
  # The helper is silent unless a newer version is published, and can never fail the hook.
  NOTE=$(bash "$(dirname "${BASH_SOURCE[0]}")/check-plugin-update.sh" --text 2>/dev/null) || NOTE=""
  [ -n "$NOTE" ] && MSG="$MSG

$NOTE"

  echo "$MSG" >&2
  exit 2
fi

exit 0
