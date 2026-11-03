#!/bin/bash
# Discovers how an existing project builds, lints and tests itself, and what might already be
# its plan. Prints JSON on stdout and exits 0 even when it finds nothing — an empty answer is
# a valid answer, and this must never be the thing that stops a run.
#
#   { "stack": "node|python|swift|go|rust|make|unknown",          (the repository root only)
#     "packageManager": "pnpm|yarn|bun|npm|null",
#     "commands": { "build": ..., "lint": ..., "test": ..., "e2e": ... },   (null when unknown)
#     "projects": [ { "path": ".|<dir>", "stack": ..., "packageManager": ...,
#                     "build": ..., "lint": ..., "test": ..., "e2e": ...,
#                     "workspaceRoot": "."|null, "planned": true|false } ],
#     "planCandidates": [ { "path": ..., "native": true|false } ],
#     "nativePlan": true|false }
#
# `stack` and `commands` describe the root exactly as they always have. `projects` is every
# project in the repository: the root when it has a manifest, every directory one or two levels
# down that has one, and every path `.bergant-workflow.json` lists under `projects`, however
# deep. A repository whose code lives in `app/` and `worker/` has no root stack at all, and
# reading only the root is how a whole sub-project's tests went unrun for a month.
#
# Nothing here is guessed: a command is only reported when the script that runs it exists, and
# a test command only when there are tests for it to find.
# Usage: bash scripts/detect-project.sh [project-root]

ROOT="${1:-$PWD}"
cd "$ROOT" 2>/dev/null || { echo '{"stack":"unknown","packageManager":null,"commands":{},"projects":[],"planCandidates":[],"nativePlan":false}'; exit 0; }

have() { command -v "$1" >/dev/null 2>&1; }

# The npm init placeholder. A `test` script that only says there are no tests is not a test
# command, and reporting it makes TEST fail on every slice of a project that never had one.
NPM_PLACEHOLDER='no test specified'

# A directory of tests, in any of the spellings stacks use. On its own it proves nothing about
# the runner — the manifest decides that — but a runner with nothing to run fails: pytest exits
# 5 on an empty collection, and `swift test` refuses a package with no test target.
has_test_dir() {
  for t in tests test Tests __tests__ spec; do [ -d "$1/$t" ] && return 0; done
  return 1
}

# detect_dir <dir> — fills D_STACK, D_PM, D_BUILD, D_LINT, D_TEST, D_E2E for one directory.
# D_STACK stays empty when the directory is not a project. `<dir>` is relative to ROOT.
detect_dir() {
  local d="$1" run f
  D_STACK=""; D_PM=""; D_BUILD=""; D_LINT=""; D_TEST=""; D_E2E=""; D_COVERS=""

  if [ -f "$d/package.json" ] && have jq; then
    D_STACK="node"
    # A workspace member usually has no lockfile of its own; the root's decides.
    for f in "$d" .; do
      if   [ -f "$f/pnpm-lock.yaml" ];    then D_PM="pnpm"
      elif [ -f "$f/yarn.lock" ];         then D_PM="yarn"
      elif [ -f "$f/bun.lockb" ] || [ -f "$f/bun.lock" ]; then D_PM="bun"
      elif [ -f "$f/package-lock.json" ]; then D_PM="npm"
      fi
      [ -n "$D_PM" ] && break
    done
    [ -z "$D_PM" ] && D_PM="npm"
    run="$D_PM run"

    script_of() { jq -r --arg k "$1" '.scripts[$k] // empty' "$d/package.json" 2>/dev/null | tr -d '\r'; }
    first_script() {
      local k body
      for k in "$@"; do
        body=$(script_of "$k")
        [ -z "$body" ] && continue
        case "$body" in *"$NPM_PLACEHOLDER"*) continue ;; esac
        printf '%s %s' "$run" "$k"; return
      done
    }
    D_BUILD=$(first_script build compile)
    D_LINT=$(first_script lint check biome eslint)
    D_TEST=$(first_script test unit "test:unit")
    D_E2E=$(first_script "test:e2e" e2e playwright cypress)
    # A workspace root covers its members only for a check whose script visibly runs across
    # the workspace. A root `test` that tests the root alone covers nothing, and assuming
    # otherwise would quietly stop every member's tests from running.
    if [ "$d" = "." ] && [ "$WS_NODE" = "true" ]; then
      local kind cmd body
      for kind in build lint test e2e; do
        eval "cmd=\$D_$(echo "$kind" | tr 'a-z' 'A-Z')"
        [ -n "$cmd" ] || continue
        body=$(script_of "${cmd##* }")
        if printf '%s' "$body" | grep -qE '(^|[[:space:]])(-r|--recursive|-ws|--workspaces|--filter)([[:space:]=]|$)|(^|[[:space:]])(turbo|nx|lerna|wsrun)[[:space:]]|yarn workspaces'; then
          D_COVERS="$D_COVERS $kind"
        fi
      done
    fi

  elif [ -f "$d/Package.swift" ]; then
    D_STACK="swift"; D_BUILD="swift build"
    # `swift test` errors out on a package with no test target, so it needs one to exist.
    if [ -d "$d/Tests" ] || grep -q 'testTarget' "$d/Package.swift" 2>/dev/null; then
      D_TEST="swift test"
    fi
    # swift-format is bundled with the toolchain, but linting with it is a choice a project
    # makes by committing a configuration. Without one, its defaults would fail most code.
    # The paths are named because `--recursive .` walks into .build and its checkouts.
    # swift-format looks for its configuration upwards from each file, so a configuration
    # anywhere between the package and the repository root applies.
    local up="$d" configured=false
    while :; do
      [ -f "$up/.swift-format" ] && { configured=true; break; }
      [ "$up" = "." ] && break
      up=$(dirname "$up")
    done
    if [ "$configured" = "true" ]; then
      local paths=" Package.swift"
      for f in Sources Tests; do [ -d "$d/$f" ] && paths="$paths $f"; done
      D_LINT="swift format lint --strict --recursive$paths"
    fi

  elif [ -f "$d/pyproject.toml" ] || [ -f "$d/setup.py" ] \
       || { [ "$d" = "." ] && { [ -f setup.cfg ] || [ -f tox.ini ] || [ -f requirements.txt ]; }; }; then
    # Off the root, only a real package manifest counts: a docs/requirements.txt for a docs
    # theme is not a Python project with tests to run.
    D_STACK="python"
    local pre="" cfgs=()
    for f in pyproject.toml setup.cfg tox.ini pytest.ini requirements.txt requirements-dev.txt; do
      [ -f "$d/$f" ] && cfgs[${#cfgs[@]}]="$d/$f"
    done
    # A uv project runs its tools from its own locked environment; a bare `pytest` there finds
    # whatever is on PATH, or nothing. A workspace member shares the root's lock.
    if [ -f "$d/uv.lock" ] \
       || { [ -f ./uv.lock ] && grep -q 'tool\.uv\.workspace' ./pyproject.toml 2>/dev/null; }; then
      pre="uv run "
    fi
    # Declared in config, or a conftest.py sitting there — both are evidence of the runner. A
    # tests/ directory on its own is not: plenty of them are run by something other than
    # pytest. And the runner is not enough on its own either: pytest with nothing to collect
    # exits 5, so there must also be somewhere for it to look.
    if { [ ${#cfgs[@]} -gt 0 ] && grep -qi "pytest" "${cfgs[@]}" 2>/dev/null; } \
       || [ -f "$d/conftest.py" ] || [ -f "$d/tests/conftest.py" ]; then
      if has_test_dir "$d" || [ -f "$d/conftest.py" ] \
         || ls "$d"/test_*.py "$d"/*_test.py >/dev/null 2>&1 \
         || grep -q 'testpaths' "${cfgs[@]}" 2>/dev/null; then
        D_TEST="${pre}pytest"
      fi
    fi
    if { [ ${#cfgs[@]} -gt 0 ] && grep -qi "ruff" "${cfgs[@]}" 2>/dev/null; } \
       || [ -f "$d/ruff.toml" ] || [ -f "$d/.ruff.toml" ]; then
      D_LINT="${pre}ruff check ."
      # Ruff is the formatter too unless the project names another one. Where black is
      # declared, ruff is only its linter, and `ruff format --check` would fail every file black
      # formatted.
      if ! grep -qiE '(^|[^a-z_-])black([^a-z_-]|$)' "${cfgs[@]}" "$d/.pre-commit-config.yaml" 2>/dev/null; then
        D_LINT="$D_LINT && ${pre}ruff format --check ."
      fi
    fi
    if [ -z "$D_LINT" ] && [ ${#cfgs[@]} -gt 0 ] && grep -qi "flake8" "${cfgs[@]}" 2>/dev/null; then
      D_LINT="${pre}flake8"
    fi

  elif [ -f "$d/go.mod" ]; then
    D_STACK="go"; D_BUILD="go build ./..."; D_TEST="go test ./..."; D_LINT="go vet ./..."

  elif [ -f "$d/Cargo.toml" ]; then
    D_STACK="rust"; D_BUILD="cargo build"; D_TEST="cargo test"; D_LINT="cargo clippy"
    # At a workspace root, plain `cargo test` runs only `default-members`; `--workspace` runs
    # every member, and only then does the root cover them.
    if [ "$d" = "." ] && [ "$WS_CARGO" = "true" ]; then
      D_BUILD="cargo build --workspace"; D_TEST="cargo test --workspace"
      D_LINT="cargo clippy --workspace"; D_COVERS=" build lint test"
    fi

  elif [ "$d" = "." ] && [ -f Makefile ]; then
    # A Makefile alone makes a project only at the root. In a subdirectory it is as likely to
    # build a document or an installer as code.
    D_STACK="make"
  fi

  # A Makefile fills whatever the stack above could not name. Plenty of Python and Go projects
  # drive everything through make, and checking it only when nothing else matched missed them.
  if [ -n "$D_STACK" ] && [ -f "$d/Makefile" ]; then
    target() { grep -qE "^$1:" "$d/Makefile" 2>/dev/null && printf 'make %s' "$1"; }
    [ -z "$D_BUILD" ] && D_BUILD=$(target build)
    [ -z "$D_LINT" ]  && D_LINT=$(target lint)
    [ -z "$D_TEST" ]  && D_TEST=$(target test)
    [ -z "$D_E2E" ]   && D_E2E=$(target e2e)
  fi

  # Two manifests in one directory are two stacks, and only the first is detected. The other is
  # reported so its commands can be set by hand instead of silently never running.
  D_ALSO=""
  if [ -n "$D_STACK" ]; then
    local m s
    for m in package.json:node Package.swift:swift pyproject.toml:python go.mod:go Cargo.toml:rust; do
      s="${m#*:}"; m="${m%%:*}"
      [ -f "$d/$m" ] && [ "$s" != "$D_STACK" ] && D_ALSO="$D_ALSO $m"
    done
  fi
  return 0
}

# Workspaces: a member's checks may be run by the root's, and running both runs every test
# twice. Only proven coverage counts — see D_COVERS above and is_member below.
WS_NODE=false; WS_CARGO=false
if [ -f package.json ] && have jq && jq -e 'has("workspaces")' package.json >/dev/null 2>&1; then WS_NODE=true; fi
[ -f pnpm-workspace.yaml ] && WS_NODE=true
grep -q '^\[workspace\]' Cargo.toml 2>/dev/null && WS_CARGO=true

detect_dir .
STACK="${D_STACK:-unknown}"; PM="${D_PM:-null}"
BUILD="$D_BUILD"; LINT="$D_LINT"; TEST="$D_TEST"; E2E="$D_E2E"

# ---- Sub-projects -----------------------------------------------------------------------------
# Directories one or two levels down: `apps/web/package.json` is found, `apps/web/x/package.json`
# is not unless the config names it. Dependency trees, build output, caches and every hidden
# directory are pruned before find descends into them, so a node_modules with ten thousand
# package.json files costs nothing. Fixture and template trees are pruned too: they hold
# manifests on purpose, and their tests belong to the project that owns them. Anything else
# can be left out with `exclude` in .bergant-workflow.json. find does not follow symlinks.
PROJ_FILE=$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/bwf-proj.$$")
: > "$PROJ_FILE"

CONFIG_PATHS=""; EXCLUDE=""
if [ -f .bergant-workflow.json ] && have jq; then
  # Paths the project itself declared, at any depth, including ones whose code is not there yet.
  CONFIG_PATHS=$(jq -r '(.projects // {}) | if type == "object" then keys[] else empty end' \
                   .bergant-workflow.json 2>/dev/null | tr -d '\r' | sed 's|^\./||; s|/$||')
  EXCLUDE=$(jq -r '(.exclude // []) | if type == "array" then .[] | strings else empty end' \
              .bergant-workflow.json 2>/dev/null | tr -d '\r' | sed 's|^\./||; s|/$||')
fi
excluded() {
  local e
  [ -n "$EXCLUDE" ] || return 1
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    case "$1" in "$e"|"$e"/*) return 0 ;; esac
  done <<EOF_EXCLUDE
$EXCLUDE
EOF_EXCLUDE
  return 1
}

SUBDIRS=$(find . -mindepth 1 -maxdepth 2 \
  \( -name '.*' -o -name node_modules -o -name vendor -o -name venv \
     -o -name dist -o -name build -o -name out -o -name target -o -name coverage \
     -o -name __pycache__ -o -name Pods -o -name DerivedData -o -name bower_components \
     -o -name fixtures -o -name __fixtures__ -o -name testdata -o -name templates \
     -o -name site-packages \) -prune \
  -o -type d -print 2>/dev/null | sed 's|^\./||' | LC_ALL=C sort)

# Whatever git ignores is not part of the project, whatever it contains. One git call for every
# directory, not one per directory. Outside a git repository nothing is ignored.
IGNORED=$(printf '%s\n' "$SUBDIRS" | git check-ignore --stdin 2>/dev/null)
is_ignored() { [ -n "$IGNORED" ] && printf '%s\n' "$IGNORED" | grep -qxF -- "$1"; }

# is_member <dir> — the workspace manifest names this directory, directly or by its parent's
# glob, and does not exclude it. Text matching, deliberately: evaluating the manifest would mean
# running the package manager.
is_member() {
  local parent f
  parent=$(dirname "$1")
  for f in package.json pnpm-workspace.yaml Cargo.toml; do
    [ -f "$f" ] || continue
    grep -E '^[[:space:]]*exclude[[:space:]]*=' "$f" 2>/dev/null | grep -qF "\"$1\"" && return 1
    grep -qE "[\"'](\./)?($1|$parent/\*|$parent/\*\*)[\"']" "$f" 2>/dev/null && return 0
  done
  return 1
}

emit() {
  # emit <path> <planned> — writes one project object for the directory just detected.
  local ws=""
  if [ "$1" != "." ] && [ "$D_STACK" = "$STACK" ]; then
    { [ "$D_STACK" = "node" ] && [ "$WS_NODE" = "true" ] && is_member "$1"; } && ws="."
    { [ "$D_STACK" = "rust" ] && [ "$WS_CARGO" = "true" ] && is_member "$1"; } && ws="."
  fi
  jq -nc --arg p "$1" --arg s "$D_STACK" --arg pm "$D_PM" --arg b "$D_BUILD" --arg l "$D_LINT" \
         --arg t "$D_TEST" --arg e "$D_E2E" --arg ws "$ws" --argjson planned "$2" \
         --arg covers "$D_COVERS" --arg also "$D_ALSO" '
    def nn: if . == "" then null else . end;
    def words: split(" ") | map(select(. != ""));
    {path: $p, stack: ($s|nn), packageManager: ($pm|nn), build: ($b|nn), lint: ($l|nn),
     test: ($t|nn), e2e: ($e|nn), workspaceRoot: ($ws|nn), planned: $planned}
    + (if ($covers|words|length) > 0 then {workspaceCovers: ($covers|words)} else {} end)
    + (if ($also|words|length) > 0 then {alsoFound: ($also|words)} else {} end)' \
    >> "$PROJ_FILE" 2>/dev/null
}

if have jq; then
  [ -n "$D_STACK" ] && emit . false
  printf '%s\n%s\n' "$SUBDIRS" "$CONFIG_PATHS" | while IFS= read -r d; do
    d="${d#./}"; d="${d%/}"
    { [ -z "$d" ] || [ "$d" = "." ]; } && continue
    case "$d" in /*|..|../*|*/../*|*/..) continue ;; esac   # never leave the repository
    declared=false
    printf '%s\n' "$CONFIG_PATHS" | grep -qxF -- "$d" && declared=true
    # A declared path is the project's own word and bypasses the filters; everything found by
    # the scan has to get past them.
    if [ "$declared" = "false" ]; then excluded "$d" && continue; is_ignored "$d" && continue; fi
    detect_dir "$d"
    if [ -n "$D_STACK" ]; then
      emit "$d" false
    elif [ "$declared" = "true" ]; then
      # A declared path with nothing there yet is a project that has been planned, not one
      # that is missing: project-init records the layout before any code exists.
      D_STACK=$(jq -r --arg p "$d" '.projects[$p].stack // empty' .bergant-workflow.json 2>/dev/null | tr -d '\r')
      emit "$d" true
    fi
  done
fi
PROJECTS=$(jq -s 'unique_by(.path)' "$PROJ_FILE" 2>/dev/null || echo '[]')
[ -n "$PROJECTS" ] || PROJECTS='[]'
rm -f "$PROJ_FILE" 2>/dev/null

# When a project has no test command, "none configured" is a bad answer to stop at: most
# repositories have no tests, and not having to work out how to add them is the point. So the
# stack decides what to recommend. No versions are named here — the runner is named, pinning is
# left to the project's own package manager at install time.
SUGGEST_TEST=""; SUGGEST_E2E=""; SUGGEST_INSTALL=""
HAS_UI=false
if [ "$STACK" = "node" ] && have jq; then
  if jq -e '((.dependencies // {}) + (.devDependencies // {}))
            | keys | any(test("^(react|vue|svelte|next|nuxt|@angular/core|solid-js)$"))' \
        package.json >/dev/null 2>&1; then
    HAS_UI=true
  fi
fi

# What the project *is* changes what testing it well looks like. A Telegram bot's logic is
# unit-testable like anything else, but the part that actually breaks — the conversation — needs
# a client driving it. Detected here, offered separately, never silently.
DOMAIN=""; INTEGRATION=""
if [ "$STACK" = "node" ] && have jq; then
  jq -e '((.dependencies // {}) + (.devDependencies // {}))
         | keys | any(test("^(telegraf|grammy|node-telegram-bot-api|telegram)$"))' \
     package.json >/dev/null 2>&1 && { DOMAIN="telegram-bot"; INTEGRATION="gramjs"; }
elif [ "$STACK" = "python" ]; then
  if grep -qiE "aiogram|python-telegram-bot|pyrogram|telethon" \
       pyproject.toml requirements.txt setup.cfg 2>/dev/null; then
    DOMAIN="telegram-bot"; INTEGRATION="telethon"
  fi
fi

if [ -z "$TEST" ]; then
  case "$STACK" in
    node)
      SUGGEST_TEST="vitest"
      SUGGEST_INSTALL="$PM add -D vitest"
      [ "$PM" = "npm" ] && SUGGEST_INSTALL="npm install -D vitest"
      [ "$HAS_UI" = "true" ] && SUGGEST_E2E="playwright"
      ;;
    python)
      SUGGEST_TEST="pytest"
      SUGGEST_INSTALL="pip install pytest"
      ;;
    go)   SUGGEST_TEST="go test"; SUGGEST_INSTALL="" ;;
    rust) SUGGEST_TEST="cargo test"; SUGGEST_INSTALL="" ;;
  esac
fi

# Documents an earlier project-init run (or a human) already produced. Their presence is what
# decides where a new run should enter, so it is reported rather than left to be guessed at.
doc() { [ -f "$1" ] && echo true || echo false; }
HAS_REQ=$(doc docs/REQUIREMENTS.md)
HAS_PRD=$(doc docs/prd.md)
HAS_ARCH=$(doc docs/architecture.md)
HAS_DS=$(doc docs/design-system.md)

# Is there a codebase already? Source files outside docs/ mean the architecture questions have
# been answered in code, whatever the documents say.
HAS_CODE=false
for d in src app lib pkg cmd internal server client packages services; do
  [ -d "$d" ] && { HAS_CODE=true; break; }
done
if [ "$HAS_CODE" = "false" ] && [ "$STACK" != "unknown" ]; then HAS_CODE=true; fi
if [ "$HAS_CODE" = "false" ] \
   && printf '%s' "$PROJECTS" | jq -e 'any(.[]; .planned | not)' >/dev/null 2>&1; then
  HAS_CODE=true
fi

# Planning output already on disk means PLANNING itself is done, not pending.
HAS_PHASES=false
for f in docs/plan/phase-*.md; do [ -f "$f" ] && { HAS_PHASES=true; break; }; done

# The phase a fresh project-init run should enter at, given what already exists.
ENTRY="INPUT_VALIDATION"
if   [ "$HAS_PHASES" = "true" ]; then ENTRY="DECOMPOSITION"
elif [ "$HAS_ARCH" = "true" ]; then ENTRY="PLANNING"
elif [ "$HAS_PRD"  = "true" ]; then ENTRY="ARCHITECTURE"
elif [ "$HAS_REQ"  = "true" ]; then ENTRY="PRD"
fi

# Plan documents. The plugin's own format wins outright; everything else is a suggestion for
# the user to confirm, never something to act on unasked.
# Candidates are accumulated as JSON objects, one per line. A pipe-delimited string could not
# survive a filename containing a pipe or a newline — it silently handed back paths that do not
# exist.
CAND_FILE=$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/bwf-cand.$$")
NATIVE="false"
add() {
  case "$(basename "$1" | tr 'A-Z' 'a-z')" in readme.md|changelog.md|license.md) return ;; esac
  [ -f "$1" ] || return
  jq -nc --arg p "$1" --argjson n "$2" '{path: $p, native: $n}' >> "$CAND_FILE" 2>/dev/null
}

for f in docs/plan/slice-*.md; do [ -f "$f" ] && { add "$f" true; NATIVE="true"; }; done
if [ "$NATIVE" = "false" ]; then
  # Walk real directory entries and match their names case-insensitively. Globbing both
  # `PLAN.md` and `plan.md` would report whichever spelling this script happens to contain,
  # not the one on disk, because macOS and Windows resolve either to the same file.
  for f in ./*.md ./*.MD docs/*.md docs/plan/*.md docs/tasks/*.md specs/*.md; do
    [ -f "$f" ] || continue
    case "$(basename "$f" | tr 'A-Z' 'a-z')" in
      plan.md|roadmap.md|todo.md|backlog.md|milestones.md|*plan*.md|*roadmap*.md|*slice*.md)
        add "${f#./}" false ;;
    esac
  done
  # Anything under docs/plan or docs/tasks is a plan document whatever it is called.
  for f in docs/plan/*.md docs/tasks/*.md; do [ -f "$f" ] && add "$f" false; done
fi

# Case-insensitive dedupe by path, capped: a docs directory with fifty files is not a menu
# anyone can answer.
CANDIDATES=$(jq -s 'unique_by(.path | ascii_downcase) | .[0:12]' "$CAND_FILE" 2>/dev/null || echo '[]')
rm -f "$CAND_FILE" 2>/dev/null

if have jq; then
  printf '%s\n%s' "$CANDIDATES" "$PROJECTS" | jq -s --arg stack "$STACK" --arg pm "$PM" \
    --arg build "$BUILD" --arg lint "$LINT" --arg test "$TEST" --arg e2e "$E2E" \
    --arg native "$NATIVE" --arg req "$HAS_REQ" --arg prd "$HAS_PRD" --arg arch "$HAS_ARCH" \
    --arg ds "$HAS_DS" --arg code "$HAS_CODE" --arg entry "$ENTRY" \
    --arg st "$SUGGEST_TEST" --arg se "$SUGGEST_E2E" --arg si "$SUGGEST_INSTALL" --arg ui "$HAS_UI" \
    --arg dom "$DOMAIN" --arg int "$INTEGRATION" '
    def nn: if . == "" then null else . end;
    {
      stack: $stack,
      packageManager: ($pm | if . == "null" then null else . end),
      commands: { build: ($build|nn), lint: ($lint|nn), test: ($test|nn), e2e: ($e2e|nn) },
      projects: (.[1] // []),
      planCandidates: (.[0] // []),
      nativePlan: ($native == "true"),
      docs: { requirements: ($req == "true"), prd: ($prd == "true"),
              architecture: ($arch == "true"), designSystem: ($ds == "true") },
      hasSourceCode: ($code == "true"),
      suggestedEntryPhase: $entry,
      hasUI: ($ui == "true"),
      domain: ($dom|nn),
      testSetup: (if $st == "" then null else
        { runner: $st, e2e: ($se|nn), install: ($si|nn), integration: ($int|nn) } end)
    }'
else
  echo '{"stack":"unknown","packageManager":null,"commands":{},"projects":[],"planCandidates":[],"nativePlan":false,"docs":{},"hasSourceCode":false,"suggestedEntryPhase":"INPUT_VALIDATION","note":"jq unavailable"}'
fi
exit 0
