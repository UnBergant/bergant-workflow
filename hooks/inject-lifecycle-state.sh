#!/bin/bash
# SessionStart(compact) hook: re-injects lifecycle state into Claude's context
# after context compression, so Claude doesn't lose track of the current step.
# Part of lifecycle system: skill=~/.claude/skills/lifecycle/SKILL.md
#
# Output goes to stdout → injected as system context.

STATE_FILE=".lifecycle-state.json"

if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# Clear awaitingCompact flag — compact just happened, IMPLEMENT can proceed
if jq -e '.awaitingCompact == true' "$STATE_FILE" > /dev/null 2>&1; then
  jq '.awaitingCompact = false' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
fi

# Inject raw lifecycle state JSON — Claude can parse it directly
echo "=== LIFECYCLE STATE ==="
cat "$STATE_FILE"
echo ""
echo "=== Resume current step. Do NOT skip steps or advance past user gates. ==="