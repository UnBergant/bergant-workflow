#!/bin/bash
# Reports a newer published version of the plugin, at most once a day. Two callers, two shapes:
#
#   - SessionStart(startup|resume), wired in hooks.json — emits the hook JSON contract, with
#     `systemMessage` (which the CLI shows the user directly) and `additionalContext` (which
#     reaches Claude). Plain stdout would only reach Claude, and whether the user ever hears
#     about it would then be the model's judgement call.
#   - check-compact-gate.sh, with --text — one plain line to append to its stderr block.
#
# Always exits 0 and stays silent on anything unexpected: no jq, no curl, no network,
# unreadable manifest, already up to date, or checked within the last 24h. A version
# notice must never be able to break a run.
#
# Opt out entirely: export BERGANT_WORKFLOW_NO_UPDATE_CHECK=1

# shellcheck source=lib-state.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-state.sh"

# Without jq every hook reads an empty value, compares it to nothing, and allows everything —
# so a missing dependency turns enforcement off. That used to happen in silence, which is the
# worst version of it: the skills still run and look like they are being enforced. Say it out
# loud, but only when a lifecycle is actually active, and never block on it.
# Probe that jq actually runs, rather than that a file by that name exists on PATH: a broken
# or half-installed jq disables enforcement exactly as thoroughly as a missing one.
if ! jq --version >/dev/null 2>&1; then
  if find_state_file >/dev/null; then
    if [ "$1" = "--text" ]; then
      echo "DEPENDENCY MISSING: jq is not installed, so the lifecycle hooks cannot read the state file and every gate is currently unenforced. Tell the user to install jq (brew install jq)."
    else
      # Static text, no interpolation — safe to hand-write as JSON without jq.
      printf '%s\n' '{"systemMessage":"bergant-workflow: jq is not installed, so lifecycle gates are NOT being enforced. Install it with: brew install jq","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"DEPENDENCY MISSING: jq is not installed, so the lifecycle hooks cannot read the state file and every gate is currently unenforced. The user has been told to install jq."}}'
    fi
  fi
  exit 0
fi

[ -n "$BERGANT_WORKFLOW_NO_UPDATE_CHECK" ] && exit 0

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)}"
INSTALLED=$(jq -r '.version // empty' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null)
[ -n "$INSTALLED" ] || exit 0

# Throttle to once a day. The stamp is disposable — losing it costs one extra check.
STAMP="${TMPDIR:-/tmp}/bergant-workflow-update-check"
NOW=$(date +%s)
if [ -f "$STAMP" ]; then
  LAST=$(head -1 "$STAMP" 2>/dev/null)
  case "$LAST" in ''|*[!0-9]*) LAST=0 ;; esac
  [ $((NOW - LAST)) -lt 86400 ] && exit 0
fi
echo "$NOW" > "$STAMP" 2>/dev/null

LATEST="$INSTALLED"
newest() { printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1; }

# Free: the marketplace clone on disk. Only as fresh as the user's last
# `claude plugin marketplace update`, so it is a hint, not the source of truth.
MP="$HOME/.claude/plugins/marketplaces/bergant-workflow/.claude-plugin/plugin.json"
if [ -f "$MP" ]; then
  V=$(jq -r '.version // empty' "$MP" 2>/dev/null)
  [ -n "$V" ] && LATEST=$(newest "$LATEST" "$V")
fi

# Authoritative: the published manifest. Short timeout, silent on failure.
if command -v curl >/dev/null 2>&1; then
  V=$(curl -fsS --max-time 3 \
    https://raw.githubusercontent.com/UnBergant/bergant-workflow/main/.claude-plugin/plugin.json \
    2>/dev/null | jq -r '.version // empty' 2>/dev/null)
  [ -n "$V" ] && LATEST=$(newest "$LATEST" "$V")
fi

[ "$LATEST" = "$INSTALLED" ] && exit 0

CMD="claude plugin marketplace update bergant-workflow && claude plugin update bergant-workflow"
FOR_CLAUDE="PLUGIN UPDATE AVAILABLE: bergant-workflow ${INSTALLED} is installed, ${LATEST} is published. If the user asks about it, the update command is: ${CMD} (restart required). Do not run it yourself — updating a plugin means running new code on their machine, and that is their call."
FOR_USER="bergant-workflow ${LATEST} is available, you have ${INSTALLED}. Update: ${CMD} (restart required)."

if [ "$1" = "--text" ]; then
  echo "$FOR_CLAUDE"
else
  jq -n --arg u "$FOR_USER" --arg c "$FOR_CLAUDE" \
    '{systemMessage: $u,
      hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
fi
exit 0
