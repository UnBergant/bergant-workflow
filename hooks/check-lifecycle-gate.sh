#!/bin/bash
# Stop hook: prevents Claude from finishing when a step was skipped.
# Part of lifecycle system: skill=skills/lifecycle/SKILL.md (bergant-workflow plugin)
#
# Exit codes:
#   0 — allow (no lifecycle active, or no steps skipped)
#   2 — block (a step was skipped, stderr message sent to Claude)
#
# Logic: iterate steps in order and remember the first one that is not "completed".
# If any LATER step is already "in_progress" or "completed", the order was broken → block.
# A user gate (gate: "user") gets the gate message, an auto step gets the order message.

STATE_FILE=".lifecycle-state.json"

# No lifecycle active → allow
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# Malformed or legacy state without a steps object → allow, nothing to enforce
if ! jq -e '.steps' "$STATE_FILE" >/dev/null 2>&1; then
  exit 0
fi

# Prevent infinite loops: if stop_hook_active, allow
INPUT=$(cat)
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
if [ "$STOP_ACTIVE" = "true" ]; then
  exit 0
fi

# Ordered steps
STEPS=("CONTEXT_CHECK" "SCOPE" "PLAN" "COMPONENTS" "IMPLEMENT" "VERIFY" "TEST" "REVIEW" "DOCUMENT" "CLOSE")

blocker=""
blocker_gate=""

for step in "${STEPS[@]}"; do
  status=$(jq -r ".steps.${step}.status // \"none\"" "$STATE_FILE" 2>/dev/null)
  gate=$(jq -r ".steps.${step}.gate // \"auto\"" "$STATE_FILE" 2>/dev/null)

  if [ -n "$blocker" ]; then
    # An earlier step is unfinished. If this later step already started → order broken.
    if [ "$status" = "in_progress" ] || [ "$status" = "completed" ]; then
      if [ "$blocker_gate" = "user" ]; then
        echo "LIFECYCLE GATE VIOLATION: Step '${blocker}' requires user confirmation (gate: user) but is not completed. You cannot proceed to '${step}' until the user confirms '${blocker}'. Stop and ask the user." >&2
      else
        echo "LIFECYCLE ORDER VIOLATION: Step '${blocker}' is not completed, but '${step}' has already started. Steps run in order. Go back and finish '${blocker}' — or, if it genuinely does not apply to this slice, auto-complete it with the reason recorded in ${STATE_FILE}." >&2
      fi
      exit 2
    fi
  elif [ "$status" != "completed" ]; then
    # First unfinished step — everything after it must still be pending.
    blocker="$step"
    blocker_gate="$gate"
  fi
done

exit 0
