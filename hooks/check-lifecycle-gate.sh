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
#   - an auto step is owed while "pending", and also while "in_progress" unless it is the step
#     the run is actually on (`currentStep`).
# If any LATER step is already "in_progress" or "completed", the order was broken → block.
#
# The currentStep exemption is what makes `start --skip-scope` work: it writes CONTEXT_CHECK
# "in_progress" with SCOPE already "completed", and legitimately stops there to ask for
# /compact. Without the exemption every such run would be blocked. With it, a step that was
# started and then abandoned — TEST left "in_progress" while the run moved on to REVIEW — is
# still caught, which is the realistic way a step disappears.

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

# Which steps are user gates is decided HERE, not in the state file. The file is written by the
# model this hook exists to constrain, so reading `gate` from it let a run demote its own gate
# to "auto" — or omit the step entirely, which used to be weaker still: a missing key was
# neither completed nor pending and therefore blocked nothing. A step absent from .steps is now
# treated as pending, so deleting keys makes the gate stricter, never looser.
USER_GATES=" SCOPE COMPONENTS VERIFY REVIEW CLOSE "

CURRENT=$(jq -r '.currentStep // ""' "$STATE_FILE" 2>/dev/null)

blocker=""
blocker_gate=""

for step in "${STEPS[@]}"; do
  status=$(jq -r ".steps.${step}.status // \"pending\"" "$STATE_FILE" 2>/dev/null)
  [ -n "$status" ] || status="pending"
  case "$USER_GATES" in *" $step "*) gate="user" ;; *) gate="auto" ;; esac

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
  elif [ "$gate" != "user" ] && { [ "$status" = "pending" ] ||
       { [ "$status" = "in_progress" ] && [ "$step" != "$CURRENT" ]; }; }; then
    # Auto step that never started, or one left running while the run moved on.
    blocker="$step"
    blocker_gate="auto"
  fi
done

exit 0
