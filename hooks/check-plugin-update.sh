#!/bin/bash
# Helper (not a hook — nothing in hooks.json points here).
# Prints a one-line update notice on stdout if a newer version of the plugin is published.
# Called by check-compact-gate.sh when it blocks at the start of a lifecycle.
#
# Always exits 0 and stays silent on anything unexpected: no jq, no curl, no network,
# unreadable manifest, already up to date, or checked within the last 24h. A version
# notice must never be able to break a run.
#
# Opt out entirely: export BERGANT_WORKFLOW_NO_UPDATE_CHECK=1

[ -n "$BERGANT_WORKFLOW_NO_UPDATE_CHECK" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

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

echo "PLUGIN UPDATE AVAILABLE: bergant-workflow ${INSTALLED} is installed, ${LATEST} is published. Also tell the user, in one line, that they can update with: claude plugin marketplace update bergant-workflow && claude plugin update bergant-workflow (restart required). Do not act on this yourself."
exit 0
