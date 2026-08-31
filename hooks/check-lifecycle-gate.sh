#!/bin/bash
# Stop hook: prevents Claude from finishing when a step was skipped.
# Part of lifecycle system: skill=skills/lifecycle/SKILL.md (bergant-workflow plugin)
#
# Exit codes:
#   0 — allow (no lifecycle active, or no steps skipped)
#   2 — block (a step was skipped, stderr message sent to Claude)
#
# Logic: iterate steps in order and remember the first step that is still owed:
#   - a user gate (gate: "user") is owed until it is "completed" — unchanged behaviour;
#   - an auto step is owed only while "pending", i.e. it never started.
# If any LATER step is already "in_progress" or "completed", the order was broken → block.
#
# Why an auto step must be "pending" and not merely un-completed: `start --skip-scope`
# writes CONTEXT_CHECK "in_progress" with SCOPE already "completed", and the run legitimately
# stops there to ask for /compact. Blocking on an in-progress auto step would fire on every
# such run. An auto step that is started and abandoned is not caught; one that is skipped is.

# shellcheck source=lib-state.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-state.sh"

STATE_FILE="$(find_state_file)" || exit 0

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
  elif [ "$gate" = "user" ] && [ "$status" != "completed" ]; then
    # Unconfirmed user gate — nothing after it may run.
    blocker="$step"
    blocker_gate="user"
  elif [ "$gate" != "user" ] && [ "$status" = "pending" ]; then
    # Auto step that never started — nothing after it may run.
    blocker="$step"
    blocker_gate="auto"
  fi
done

exit 0
