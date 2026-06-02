#!/bin/bash
# Stop hook: prevents Claude from finishing when a user gate was skipped.
# Part of lifecycle system: skill=~/.claude/skills/lifecycle/SKILL.md
#
# Exit codes:
#   0 — allow (no lifecycle active, or no gates skipped)
#   2 — block (a user gate was skipped, stderr message sent to Claude)
#
# Logic: iterate steps in order. If we find a step with gate:"user"
# that is NOT "completed", but a later step is "in_progress" or "completed",
# then a gate was skipped → block.

STATE_FILE=".lifecycle-state.json"

# No lifecycle active → allow
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# Prevent infinite loops: if stop_hook_active, allow
INPUT=$(cat)
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
if [ "$STOP_ACTIVE" = "true" ]; then
  exit 0
fi

# Ordered steps
STEPS=("CONTEXT_CHECK" "SCOPE" "PLAN" "IMPLEMENT" "VERIFY" "TEST" "REVIEW" "DOCUMENT" "CLOSE")

# Read step statuses and gates
found_incomplete_gate=false
gate_step=""

for step in "${STEPS[@]}"; do
  status=$(jq -r ".steps.${step}.status // \"none\"" "$STATE_FILE" 2>/dev/null)
  gate=$(jq -r ".steps.${step}.gate // \"auto\"" "$STATE_FILE" 2>/dev/null)

  if [ "$found_incomplete_gate" = true ]; then
    # We already found an incomplete user gate earlier.
    # If this later step is in_progress or completed → gate was skipped.
    if [ "$status" = "in_progress" ] || [ "$status" = "completed" ]; then
      echo "LIFECYCLE GATE VIOLATION: Step '${gate_step}' requires user confirmation (gate: user) but is not completed. You cannot proceed to '${step}' until the user confirms '${gate_step}'. Stop and ask the user." >&2
      exit 2
    fi
  fi

  # Mark if we found an incomplete user gate
  if [ "$gate" = "user" ] && [ "$status" != "completed" ]; then
    found_incomplete_gate=true
    gate_step="$step"
  fi
done

exit 0