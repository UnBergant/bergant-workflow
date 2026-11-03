#!/bin/bash
# What the lifecycle runs for one kind of check, across every project in the repository.
# Discovery is detect-project.sh's; this applies `.bergant-workflow.json` on top of it and says,
# for each project, exactly which command runs, from where, and why.
#
#   bash scripts/project-commands.sh <build|lint|test|e2e> [project-root]
#     → [ { "path", "stack", "command", "shell", "source", "status" } ]
#   bash scripts/project-commands.sh markdown [project-root]
#     → the "Project commands" section, the same list written for people
#   bash scripts/project-commands.sh run <build|lint|test|e2e> [project-root]
#     → runs every `run` entry in turn from the repository root, one failure never stopping the
#       next, then prints one PASS/FAIL/SKIP line per project. Exits 1 if any failed, 3 with
#       "NOTHING RAN" when there was nothing to run — no tests is not the same as tests
#       passing — and 0 otherwise.
#
# `shell` is the line to run from the repository root. `status` is one of:
#   run      — run it
#   none     — the project has no such command (reported as a skip, never substituted)
#   skipped  — `.bergant-workflow.json` says to leave this project out
#   covered  — a workspace member whose root already runs this check for it
#   planned  — declared, but its code does not exist yet
# `source` says where the command came from: `detected`, `override` (projects.<path>.<kind>)
# or `config` (the top-level commands.<kind>).
#
# Rediscovered on every call, so a sub-project added since adoption is picked up without
# anyone editing the config. A broken `.bergant-workflow.json` is an error (exit 2), never an
# empty plan: an empty plan reads as "nothing to check", which is how checks stop running.

usage() { echo "usage: project-commands.sh [run] <build|lint|test|e2e> [project-root] | markdown [project-root]" >&2; exit 2; }
RUN=false
if [ "$1" = "run" ]; then RUN=true; shift; fi
KIND="$1"
ROOT="${2:-$PWD}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$KIND" in
  build|lint|test|e2e) ;;
  markdown) [ "$RUN" = "true" ] && usage ;;
  *) usage ;;
esac
command -v jq >/dev/null 2>&1 || { echo "project-commands.sh: jq is required" >&2; exit 2; }
cd "$ROOT" 2>/dev/null || { echo "project-commands.sh: no such directory: $ROOT" >&2; exit 2; }

DETECTED=$(bash "$HERE/detect-project.sh" . 2>/dev/null)
printf '%s' "$DETECTED" | jq -e . >/dev/null 2>&1 || DETECTED='{"projects":[]}'

CONFIG='{}'
if [ -f .bergant-workflow.json ]; then
  # Exactly one JSON object: `{...} trailing junk` prints the object before it fails, so the
  # status is what decides, not whether something came out.
  if CONFIG=$(jq -cse 'if length == 1 and (.[0] | type) == "object" then .[0] else error("not one object") end' \
                .bergant-workflow.json 2>/dev/null); then
    CONFIG=$(printf '%s' "$CONFIG" | tr -d '\r')
  else
    CONFIG=""
  fi
  if [ -z "$CONFIG" ]; then
    echo "project-commands.sh: .bergant-workflow.json is not a valid JSON object; fix it or re-run adopt" >&2
    exit 2
  fi
fi

# The rules live in one jq program so the JSON a step runs and the markdown a person reads can
# never disagree.
PROGRAM='
def shq: (if startswith("-") then "./" + . else . end)
  | if test("^[A-Za-z0-9._/@+-]+$") then . else @sh end;
def norm: sub("^\\./"; "") | sub("/$"; "");
# A command that is more than an && chain is grouped, so nothing in it runs when the cd fails.
def line($cwd; $cmd): if $cwd == "." then $cmd
  elif ($cmd | gsub("&&"; "") | test("[;|&\n]")) then "cd \($cwd | shq) && (\($cmd))"
  else "cd \($cwd | shq) && \($cmd)" end;

def resolve($k):
  ($cfg.commands // {}) as $c
  # Keys are matched as detection spells paths: `./web` and `web/` both mean `web`.
  | ($cfg.projects // {} | if type == "object" then with_entries(.key |= norm) else {} end) as $po
  | ($det.projects // []) as $ps
  | (if ($c | has($k)) then $c[$k] else null end) as $rootcmd
  # A top-level command written as `cd <sub-project> && ...` is that sub-project'\''s command,
  # not an extra one. Configurations from before discovery existed say exactly this, and
  # running it beside the detected command would run the same tests twice.
  | (if ($rootcmd | type) == "string" and ($rootcmd | test("&&\\s*cd\\s") | not) then
       ([$rootcmd | capture("^\\s*cd\\s+(?<p>\"[^\"]+\"|'\''[^'\'']+'\''|[^\\s;&|]+)\\s*&&")]
        | first | .p // null
        | if . then ltrimstr("\"") | rtrimstr("\"") | ltrimstr("'\''") | rtrimstr("'\''") | norm
          else . end)
     else null end) as $target
  | ([$ps[].path] | index($target)) as $hit
  | (if $target != null and $hit != null and $target != "." then $target else null end) as $absorbed
  | [ $ps[] as $p
      | ($po[$p.path] // {} | if type == "object" then . else {} end) as $o
      | (if $o.skip == true then {command: null, cwd: $p.path, source: "override"}
         elif ($o | has($k)) then {command: $o[$k], cwd: $p.path, source: "override"}
         elif $p.path == $absorbed then {command: $rootcmd, cwd: ".", source: "config"}
         elif $p.path == "." and ($c | has($k)) and $absorbed == null then
           {command: $c[$k], cwd: ".", source: "config"}
         else {command: $p[$k], cwd: $p.path, source: "detected"} end) as $r
      | {path: $p.path, stack: $p.stack, command: $r.command,
         shell: (if $r.command then line($r.cwd; $r.command) else null end),
         source: $r.source,
         status: (if $o.skip == true then "skipped"
                  elif $p.planned and $r.source != "override" then "planned"
                  elif $r.command == null then "none"
                  else "run" end),
         workspaceRoot: $p.workspaceRoot}
        + (if $p.alsoFound then {note: "also has \($p.alsoFound | join(", ")); set its commands under projects in .bergant-workflow.json"} else {} end) ]
  | . as $rows
  # A workspace member is covered only when the root runs this kind of check with the very
  # command detection proved runs across the workspace — whether it was detected or copied into
  # `commands` at adoption. A different root command is the user'\''s, and nothing is known about
  # what it covers. A member with its own override is never covered: it asked to run.
  | ([$ps[] | select(.path == ".")][0] // {}) as $rootp
  | ([$rows[] | select(.path == "." and .status == "run" and .command == $rootp[$k])] | length > 0
     and (($rootp.workspaceCovers // []) | index($k)) != null) as $rootCovers
  | [ $rows[] | if .workspaceRoot != null and $rootCovers and .status == "run"
                   and .source == "detected"
                then .status = "covered" else . end | del(.workspaceRoot) ]
  # No root project, but a root command that is not about any one sub-project: it runs at the
  # root, beside the rest. A repository-wide schema check is the usual case.
  + (if ([$ps[].path] | index(".")) == null and ($rootcmd | type) == "string" and $absorbed == null
     then [{path: ".", stack: null, command: $rootcmd, shell: $rootcmd,
            source: "config", status: "run"}]
     else [] end);

def code: if test("`") then "`` \(.) ``" else "`\(.)`" end;
def mdcell($row): if $row.status == "run" then ($row.shell | code)
  elif $row.status == "covered" then "run by the workspace root"
  elif $row.status == "skipped" then "skipped (configured)"
  elif $row.status == "planned" then "not created yet"
  else "none" end;

if $kind == "markdown" then
  (["build", "lint", "test", "e2e"] | map({key: ., value: resolve(.)}) | from_entries) as $all
  | ($all.e2e | any(.status == "run")) as $withE2E
  | ([$all[][] | .path] | unique) as $paths
  | def cell($kind; $p): mdcell(first($all[$kind][] | select(.path == $p)) // {status: "none"});
    [ "<!-- bergant-workflow:project-commands:start — generated by scripts/project-commands.sh; edit .bergant-workflow.json, not this block -->",
      "## Project commands",
      "",
      "Every project in this repository and how to build, lint and test it. The lifecycle runs exactly these, so running them yourself checks what it will check. Each line runs from the repository root.",
      "",
      (if ($paths | length) == 0 then "No project manifest found yet.", "" else empty end),
      ( $paths[] as $p
        | (first($all[][] | select(.path == $p and .stack != null)) // {}) as $any
        | "### `\($p)`\(if $any.stack then " (\($any.stack))" else "" end)",
          "",
          (first($all[][] | select(.path == $p and .note != null)) // {} | if .note then "Note: \(.note).", "" else empty end),
          "- build: \(cell("build"; $p))",
          "- lint: \(cell("lint"; $p))",
          "- test: \(cell("test"; $p))",
          (if $withE2E then "- e2e: \(cell("e2e"; $p))" else empty end),
          "" ),
      "<!-- bergant-workflow:project-commands:end -->" ]
  | join("\n")
else
  resolve($kind)
end
'

PLAN=$(jq -n --argjson det "$DETECTED" --argjson cfg "$CONFIG" --arg kind "$KIND" "$PROGRAM") \
  || { echo "project-commands.sh: could not resolve commands from .bergant-workflow.json" >&2; exit 2; }

if [ "$KIND" = "markdown" ]; then
  printf '%s\n' "$(printf '%s' "$PLAN" | jq -r . | tr -d '\r')"
  exit 0
fi
if [ "$RUN" = "false" ]; then
  printf '%s\n' "$PLAN"
  exit 0
fi

# Run mode. Sequential on purpose: two test suites at once compete for the same machine, and
# their output interleaves into something nobody can read.
SUMMARY=""; FAILED=0; RAN=0
# Ctrl-C stops the whole run, even when the child handles the signal and exits 0 itself.
trap 'echo; echo "interrupted"; exit 130' INT TERM
# jq -r on Windows can end lines with \r; every value read back here is stripped of it.
N=$(printf '%s' "$PLAN" | jq 'length' | tr -d '\r')
i=0
while [ "$i" -lt "$N" ]; do
  row=$(printf '%s' "$PLAN" | jq -c ".[$i]")
  i=$((i + 1))
  path=$(printf '%s' "$row" | jq -r .path | tr -d '\r')
  status=$(printf '%s' "$row" | jq -r .status | tr -d '\r')
  if [ "$status" != "run" ]; then
    SUMMARY="$SUMMARY
SKIP $path: $status"
    continue
  fi
  line=$(printf '%s' "$row" | jq -r .shell | tr -d '\r')
  echo "==> $path: $line"
  # CDPATH would let `cd web` land in some other `web` entirely.
  CDPATH= bash -c "$line"
  rc=$?
  RAN=$((RAN + 1))
  # 130 is Ctrl-C: the person wants it to stop, not to watch the next suite start.
  if [ "$rc" -eq 130 ]; then echo "interrupted"; exit 130; fi
  if [ "$rc" -eq 0 ]; then SUMMARY="$SUMMARY
PASS $path: $line"
  else FAILED=$((FAILED + 1)); SUMMARY="$SUMMARY
FAIL $path (exit $rc): $line"; fi
done
echo
echo "== $KIND summary"
printf '%s\n' "$SUMMARY" | sed '/^$/d'
if [ "$RAN" -eq 0 ]; then echo "NOTHING RAN: no project has a $KIND command"; exit 3; fi
[ "$FAILED" -eq 0 ]
