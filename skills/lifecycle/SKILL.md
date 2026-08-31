---
name: lifecycle
description: Orchestrate feature lifecycle — track steps, enforce gates, dispatch sub-agents. Use when starting a new task, checking lifecycle status, or advancing to the next step.
user-invocable: true
disable-model-invocation: false
allowed-tools: Agent, Read, Bash
argument-hint: "[start|next|status|advance|complete <step>]"
---

# Lifecycle Orchestrator

Runs one slice to a merged PR. It does **not** need `project-init` to have run: on a project
with no plan documents the scope comes from what the user described at `start`, and SCOPE is
the gate that pins it down. Use `project-init` only when what to build has not been decided.

## Routing

**`status` (or no arguments):** execute INLINE — read `.lifecycle-state.json` and display the status table directly. Do NOT launch an agent. See "Status display" section below.

This skill's directory (its reference files live here) — resolved at runtime: !`echo ${CLAUDE_SKILL_DIR}`

**All other commands** (`start`, `next`, `advance`, `complete`, `recover`): launch `Agent(general-purpose)` with the prompt below. Replace `SKILL_DIR` with the absolute path printed just above:

```
Read these files in order:
1. SKILL_DIR/references/state-schema.md — state file structure
2. SKILL_DIR/references/project-config.md — the project's commands and plan location
3. SKILL_DIR/references/steps.md — find the section for the CURRENT step only

Execute lifecycle command: $ARGUMENTS
State file: .lifecycle-state.json

Critical rules:
1. NEVER skip a step. Order: CONTEXT_CHECK → SCOPE → PLAN → COMPONENTS → IMPLEMENT → VERIFY → TEST → REVIEW → DOCUMENT → CLOSE.
2. NEVER advance past a user gate without `/bergant-workflow:lifecycle complete <step>`.
3. Always update state file after every transition.
4. Always read state file before any action.
5. Use Agent tool for heavy work (IMPLEMENT subtasks, REVIEW).
6. Task context comes from the plan files named by `planGlob` in `.bergant-workflow.json` (default `docs/plan/slice-*.md`) — do NOT use Jira MCP. Read the relevant plan file to understand task scope and dependencies. If `planGlob` is `null`, the project has no plan documents and the scope comes from what the user described at `start`; SCOPE is then the gate that pins it down.
7. GitHub operations via the `gh` CLI (`gh pr create`, `gh pr merge`). Never use interactive
   flags — pass `--title`/`--body` explicitly. If `gh` is missing or unauthenticated, fall back
   to GitHub MCP (`mcp__github__*`).
8. **Never assume the toolchain.** Build, lint and test commands come from `commands` in
   `.bergant-workflow.json`. A command recorded as `null` means the project has none — say so
   and move on. Never fall back to `npm run <anything>` on a project that never asked for it.
9. **Never mutate Git beyond what the current step prescribes.** No `stash`, no `checkout -f`,
   no `clean`, no `add -A`, no `branch -D`, no force push. If the tree is not what the step
   expects, stop and ask.
10. When a task is completed, tick its checkbox in the corresponding `docs/plan/slice-*.md` file.
11. **Live checklist, if the session has one.** If a checklist tool such as `TodoWrite` is
    available, mirror the step statuses into it so progress renders in the UI. It is a mirror,
    never the record — `.lifecycle-state.json` is the record, and `status` reads from it. Some
    builds do not expose the tool at all; when it is missing, skip this silently.

When you hit a user gate (STOP HERE), return the gate message. Return a concise summary of what was done and what the user needs to do next.

IMPORTANT: When writing or updating .lifecycle-state.json, ALWAYS use the Write tool — NEVER use Bash with cat/heredoc/echo redirect. Heredoc commands trigger permission prompts.
```

If the agent returns an error, display it to the user without re-running.

## Status display

Read `.lifecycle-state.json`. If no file exists, say "No active lifecycle. Use `/bergant-workflow:lifecycle start <task-name>` to begin."

Display a formatted table:
- Each step with status emoji (⏳ pending, 🔄 in_progress, ✅ completed)
- Current step highlighted
- User gates marked with 🚧
- Subtask progress for IMPLEMENT step
- What the next action should be

## Commands (summary)

| Command | Action |
|---------|--------|
| `start <task>` | Git preflight, then initialize state with `awaitingCompact: true`. Supports `--skip-scope`. |
| `advance` | Move to next step (validates current is completed, respects gates). |
| `complete <step>` | User confirms a gate. Marks step completed, advances. |
| `adopt` | Learn an existing project: detect its build/lint/test commands and any plan it already has, confirm both with the user, write `.bergant-workflow.json`. Runs automatically on the first `start` when that file is missing. |
| `recover` | Reconstruct state from git/build/tests when state file is lost. |
| `skip-compact` | The user's deliberate opt-out of a pending compact. Sets `awaitingCompact: false` and records `compactSkippedAt` plus the step it was skipped before. Only ever run when the user asked for it in so many words — never to get past a block on your own initiative. |
| `next` | Read `docs/plan/slice-*.md` files, find first ⏳ task in the lowest incomplete slice, run `start` on it. |

## State File Location

`.lifecycle-state.json` — in the project root (NOT under `.claude/`, which would trigger a
write-permission prompt on every update). This file is gitignored and deleted on CLOSE.

## Optional dependencies

These power specific steps. The first time a step needs one and it's missing, offer the user a
**one-time choice — install it now or skip the step** (note the skip). Never hard-block the
lifecycle on a missing optional tool.

| Dependency | Step | If missing |
|------------|------|-----------|
| `jq` (required by the hooks) | compact/gate hooks | hooks no-op → gate enforcement is OFF; warn and suggest `brew install jq` |
| A second-opinion skill driving an external model (e.g. `toxic-opinion` + Codex CLI — not bundled) | SCOPE second opinion | skip with a note in the approved scope |
| A dual-review skill (e.g. `toxic-review` — not bundled) | REVIEW | single in-house review Agent only, note which was used |
| `gh` CLI (authenticated) | CLOSE (PR create/merge) | fall back to GitHub MCP (`mcp__github__*`); if neither is available, stop and let the user open/merge the PR manually |
| Storybook | COMPONENTS | offer to add it, else skip the component-review substep |
| Design agents (`ui-agent`/`ux-agent`/`visual-agent`/`brand-agent` — not bundled) | COMPONENTS / design tasks | proceed with a `general-purpose` agent for the design pass, note it |
