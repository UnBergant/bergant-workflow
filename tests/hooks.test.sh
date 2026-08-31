#!/bin/bash
# Portable smoke tests for the lifecycle hooks. No framework: every case builds a state file,
# runs one hook, and asserts its exit code and message. Run from anywhere:
#   bash tests/hooks.test.sh
# Exits non-zero if any case fails.

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 1

PASS=0
FAIL=0

# state <STEP=status ...> — writes .lifecycle-state.json with the real gate layout
PY=$(command -v python3 || command -v python)
[ -n "$PY" ] || { echo "python3 or python is required to run these tests"; exit 1; }

state() {
  "$PY" -c '
import json,sys
steps=["CONTEXT_CHECK","SCOPE","PLAN","COMPONENTS","IMPLEMENT","VERIFY","TEST","REVIEW","DOCUMENT","CLOSE"]
gates={"SCOPE","COMPONENTS","VERIFY","REVIEW","CLOSE"}
over=dict(a.split("=") for a in sys.argv[1:] if "=" in a)
extra={k[1:]:(v=="true" if v in ("true","false") else v) for k,v in
       (a.split("=") for a in sys.argv[1:] if a.startswith("@"))}
doc={"task":"t","steps":{s:{"status":over.get(s,"pending"),
     "gate":"user" if s in gates else "auto"} for s in steps}}
doc.update(extra)
json.dump(doc,open(".lifecycle-state.json","w"))' "$@"
}

# check <name> <expected-exit> <expected-substring-or-EMPTY> <hook> [stdin]
check() {
  local name="$1" want="$2" needle="$3" hook="$4" stdin="${5:-{\"stop_hook_active\":false\}}"
  local out code
  out=$(echo "$stdin" | BERGANT_WORKFLOW_NO_UPDATE_CHECK=1 bash "$HOOKS/$hook" 2>&1 >/dev/null)
  code=$?
  if [ "$code" != "$want" ]; then
    echo "FAIL $name — exit $code, wanted $want"; FAIL=$((FAIL+1)); return
  fi
  if [ "$needle" != "EMPTY" ] && ! printf '%s' "$out" | grep -q "$needle"; then
    echo "FAIL $name — message missing '$needle': $out"; FAIL=$((FAIL+1)); return
  fi
  if [ "$needle" = "EMPTY" ] && [ -n "$out" ]; then
    echo "FAIL $name — expected no output, got: $out"; FAIL=$((FAIL+1)); return
  fi
  echo "ok   $name"; PASS=$((PASS+1))
}

echo "# check-lifecycle-gate.sh"
rm -f .lifecycle-state.json
check "no lifecycle -> allow" 0 EMPTY check-lifecycle-gate.sh

state CONTEXT_CHECK=completed SCOPE=completed PLAN=completed COMPONENTS=completed \
      IMPLEMENT=completed VERIFY=completed TEST=completed REVIEW=completed \
      DOCUMENT=completed CLOSE=completed
check "everything done -> allow" 0 EMPTY check-lifecycle-gate.sh

state CONTEXT_CHECK=completed SCOPE=completed PLAN=completed COMPONENTS=completed \
      IMPLEMENT=completed VERIFY=in_progress
check "mid-run, waiting on a gate -> allow" 0 EMPTY check-lifecycle-gate.sh

state CONTEXT_CHECK=completed SCOPE=completed PLAN=completed COMPONENTS=completed \
      IMPLEMENT=completed VERIFY=completed REVIEW=in_progress
check "TEST skipped -> ORDER VIOLATION" 2 "LIFECYCLE ORDER VIOLATION" check-lifecycle-gate.sh

state CONTEXT_CHECK=completed SCOPE=completed PLAN=completed COMPONENTS=completed \
      IMPLEMENT=completed VERIFY=in_progress TEST=in_progress
check "user gate skipped -> GATE VIOLATION" 2 "LIFECYCLE GATE VIOLATION" check-lifecycle-gate.sh

state CONTEXT_CHECK=in_progress SCOPE=completed
check "start --skip-scope -> allow" 0 EMPTY check-lifecycle-gate.sh

state CONTEXT_CHECK=completed SCOPE=completed PLAN=completed COMPONENTS=completed \
      IMPLEMENT=completed VERIFY=completed REVIEW=in_progress
check "violation but stop_hook_active -> allow" 0 EMPTY check-lifecycle-gate.sh '{"stop_hook_active":true}'

echo '{"task":"t"}' > .lifecycle-state.json
check "legacy state, no steps -> allow" 0 EMPTY check-lifecycle-gate.sh

echo
echo "# check-compact-gate.sh"
rm -f .lifecycle-state.json
check "no lifecycle -> allow" 0 EMPTY check-compact-gate.sh
state @awaitingCompact=true @currentStep=CONTEXT_CHECK CONTEXT_CHECK=in_progress
check "awaiting compact -> block" 2 "COMPACT REQUIRED" check-compact-gate.sh
state @awaitingCompact=false CONTEXT_CHECK=in_progress
check "compact done -> allow" 0 EMPTY check-compact-gate.sh

echo
echo "# check-plugin-update.sh"
FAKE="$WORK/fakehome"
mkdir -p "$FAKE/.claude/plugins/marketplaces/bergant-workflow/.claude-plugin" "$WORK/installed/.claude-plugin"
echo '{"version":"9.9.9"}' > "$FAKE/.claude/plugins/marketplaces/bergant-workflow/.claude-plugin/plugin.json"
echo '{"version":"0.0.1"}' > "$WORK/installed/.claude-plugin/plugin.json"

out=$(HOME="$FAKE" TMPDIR="$WORK/t1" CLAUDE_PLUGIN_ROOT="$WORK/installed" \
      bash "$HOOKS/check-plugin-update.sh" 2>/dev/null)
mkdir -p "$WORK/t1"
out=$(HOME="$FAKE" TMPDIR="$WORK/t1" CLAUDE_PLUGIN_ROOT="$WORK/installed" \
      bash "$HOOKS/check-plugin-update.sh" 2>/dev/null)
case "$out" in
  *"0.0.1 is installed, 9.9.9 is published"*) echo "ok   stale install -> notice names both versions"; PASS=$((PASS+1)) ;;
  *) echo "FAIL stale install -> got: ${out:-<empty>}"; FAIL=$((FAIL+1)) ;;
esac

out=$(HOME="$FAKE" TMPDIR="$WORK/t1" CLAUDE_PLUGIN_ROOT="$WORK/installed" \
      bash "$HOOKS/check-plugin-update.sh" 2>/dev/null)
if [ -z "$out" ]; then echo "ok   second run same day -> throttled"; PASS=$((PASS+1))
else echo "FAIL throttle -> got: $out"; FAIL=$((FAIL+1)); fi

mkdir -p "$WORK/t2"
out=$(BERGANT_WORKFLOW_NO_UPDATE_CHECK=1 HOME="$FAKE" TMPDIR="$WORK/t2" \
      CLAUDE_PLUGIN_ROOT="$WORK/installed" bash "$HOOKS/check-plugin-update.sh" 2>/dev/null)
if [ -z "$out" ]; then echo "ok   opt-out env -> silent"; PASS=$((PASS+1))
else echo "FAIL opt-out -> got: $out"; FAIL=$((FAIL+1)); fi

echo
echo "# hooks.json wiring"
cat > "$WORK/wiring.py" <<'PYW'
import json, sys
d = json.load(open(sys.argv[1]))["hooks"]
out = []
for event, entries in sorted(d.items()):
    for e in entries:
        for h in e["hooks"]:
            script = h["command"].rsplit("/", 1)[-1].strip('"')
            out.append(event + ":" + e.get("matcher", "*") + ":" + script)
print("\n".join(sorted(out)))
PYW
WIRING=$("$PY" "$WORK/wiring.py" "$HOOKS/hooks.json")

for want in \
  "SessionStart:compact:inject-lifecycle-state.sh" \
  "SessionStart:startup|resume:check-plugin-update.sh" \
  "PreToolUse:Agent:check-compact-gate.sh" \
  "Stop:*:check-lifecycle-gate.sh"; do
  if printf '%s\n' "$WIRING" | grep -qxF "$want"; then
    echo "ok   wired $want"; PASS=$((PASS+1))
  else
    echo "FAIL missing wiring $want"; FAIL=$((FAIL+1))
  fi
done

for f in "$HOOKS"/*.sh; do
  if bash -n "$f" 2>/dev/null; then echo "ok   parses $(basename "$f")"; PASS=$((PASS+1))
  else echo "FAIL syntax error in $f"; FAIL=$((FAIL+1)); fi
done

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
