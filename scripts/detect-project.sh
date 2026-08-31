#!/bin/bash
# Discovers how an existing project builds, lints and tests itself, and what might already be
# its plan. Prints JSON on stdout and exits 0 even when it finds nothing — an empty answer is
# a valid answer, and this must never be the thing that stops a run.
#
#   { "stack": "node|python|go|rust|make|unknown",
#     "packageManager": "pnpm|yarn|bun|npm|null",
#     "commands": { "build": ..., "lint": ..., "test": ..., "e2e": ... },   (null when unknown)
#     "planCandidates": [ { "path": ..., "native": true|false } ],
#     "nativePlan": true|false }
#
# Nothing here is guessed: a command is only reported when the script that runs it exists.
# Usage: bash scripts/detect-project.sh [project-root]

ROOT="${1:-$PWD}"
cd "$ROOT" 2>/dev/null || { echo '{"stack":"unknown","packageManager":null,"commands":{},"planCandidates":[],"nativePlan":false}'; exit 0; }

have() { command -v "$1" >/dev/null 2>&1; }
STACK="unknown"; PM="null"
BUILD=""; LINT=""; TEST=""; E2E=""

if [ -f package.json ] && have jq; then
  STACK="node"
  if   [ -f pnpm-lock.yaml ];    then PM="pnpm"
  elif [ -f yarn.lock ];         then PM="yarn"
  elif [ -f bun.lockb ];         then PM="bun"
  elif [ -f package-lock.json ]; then PM="npm"
  else PM="npm"; fi

  run="$PM run"
  [ "$PM" = "npm" ] && run="npm run"

  script_exists() { jq -e --arg k "$1" '.scripts // {} | has($k)' package.json >/dev/null 2>&1; }
  first_script() { for k in "$@"; do script_exists "$k" && { printf '%s %s' "$run" "$k"; return; }; done; }

  BUILD=$(first_script build compile)
  LINT=$(first_script lint check biome eslint)
  TEST=$(first_script test unit "test:unit")
  E2E=$(first_script "test:e2e" e2e playwright cypress)

elif [ -f pyproject.toml ] || [ -f setup.cfg ] || [ -f tox.ini ]; then
  STACK="python"
  # Declared in config, or a conftest.py sitting there — both are evidence. A tests/ directory
  # on its own is not: plenty of them are run by something other than pytest.
  if grep -qi "pytest" pyproject.toml setup.cfg tox.ini 2>/dev/null \
     || [ -f conftest.py ] || [ -f pytest.ini ] || [ -f tests/conftest.py ]; then
    TEST="pytest"
  fi
  grep -qi "ruff" pyproject.toml 2>/dev/null && LINT="ruff check ."
  [ -z "$LINT" ] && grep -qi "flake8" pyproject.toml setup.cfg tox.ini 2>/dev/null && LINT="flake8"

elif [ -f go.mod ]; then
  STACK="go"; BUILD="go build ./..."; TEST="go test ./..."; LINT="go vet ./..."

elif [ -f Cargo.toml ]; then
  STACK="rust"; BUILD="cargo build"; TEST="cargo test"; LINT="cargo clippy"

elif [ -f Makefile ]; then
  STACK="make"
fi

# A Makefile fills whatever the stack above could not name. Plenty of Python and Go projects
# drive everything through make, and checking it only when nothing else matched missed them.
if [ -f Makefile ]; then
  target() { grep -qE "^$1:" Makefile 2>/dev/null && printf 'make %s' "$1"; }
  [ -z "$BUILD" ] && BUILD=$(target build)
  [ -z "$LINT" ]  && LINT=$(target lint)
  [ -z "$TEST" ]  && TEST=$(target test)
  [ -z "$E2E" ]   && E2E=$(target e2e)
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

# The phase a fresh project-init run should enter at, given what already exists.
ENTRY="INPUT_VALIDATION"
if   [ "$HAS_ARCH" = "true" ]; then ENTRY="PLANNING"
elif [ "$HAS_PRD"  = "true" ]; then ENTRY="ARCHITECTURE"
elif [ "$HAS_REQ"  = "true" ]; then ENTRY="PRD"
fi

# Plan documents. The plugin's own format wins outright; everything else is a suggestion for
# the user to confirm, never something to act on unasked.
CANDIDATES=""
NATIVE="false"
add() {
  case "$(basename "$1" | tr 'A-Z' 'a-z')" in readme.md|changelog.md|license.md) return ;; esac
  [ -f "$1" ] && CANDIDATES="${CANDIDATES}${1}|${2}"$'\n'
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

# Case-insensitive dedupe: macOS and Windows filesystems are case-insensitive, so PLAN.md and
# plan.md are one file matched by two globs, and offering it twice looks broken.
CANDIDATES=$(printf '%s' "$CANDIDATES" | grep -v '^$' | sort -u |
  awk '{ k = tolower($0); if (!(k in seen)) { seen[k] = 1; print } }' | head -12)

if have jq; then
  printf '%s' "$CANDIDATES" | jq -R -s --arg stack "$STACK" --arg pm "$PM" \
    --arg build "$BUILD" --arg lint "$LINT" --arg test "$TEST" --arg e2e "$E2E" \
    --arg native "$NATIVE" --arg req "$HAS_REQ" --arg prd "$HAS_PRD" --arg arch "$HAS_ARCH" \
    --arg ds "$HAS_DS" --arg code "$HAS_CODE" --arg entry "$ENTRY" '
    def nn: if . == "" then null else . end;
    {
      stack: $stack,
      packageManager: ($pm | if . == "null" then null else . end),
      commands: { build: ($build|nn), lint: ($lint|nn), test: ($test|nn), e2e: ($e2e|nn) },
      planCandidates: (split("\n") | map(select(length > 0)) | map(split("|") | {path: .[0], native: (.[1] == "true")})),
      nativePlan: ($native == "true"),
      docs: { requirements: ($req == "true"), prd: ($prd == "true"),
              architecture: ($arch == "true"), designSystem: ($ds == "true") },
      hasSourceCode: ($code == "true"),
      suggestedEntryPhase: $entry
    }'
else
  echo '{"stack":"unknown","packageManager":null,"commands":{},"planCandidates":[],"nativePlan":false,"docs":{},"hasSourceCode":false,"suggestedEntryPhase":"INPUT_VALIDATION","note":"jq unavailable"}'
fi
exit 0
