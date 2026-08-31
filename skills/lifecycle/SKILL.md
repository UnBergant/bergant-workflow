---
name: lifecycle
description: Orchestrate feature lifecycle — track steps, enforce gates, dispatch sub-agents. Use when starting a new task, checking lifecycle status, or advancing to the next step.
user-invocable: true
disable-model-invocation: false
allowed-tools: Agent, Task, Read, Bash
argument-hint: "[start|next|status|advance|complete <step>|adopt|skip-compact|recover]"
---

# Lifecycle Orchestrator

<!-- allowed-tools lists only what this skill needs INLINE: Read for `status`, Bash for
     `skip-compact`'s jq write, and the sub-agent tool under both names the harness uses. Every
     other command runs in a spawned agent, which carries its own tools. If you ever add an
     inline step that writes a file, add Write here too — otherwise it will fail the day this
     field starts being enforced. -->

Runs one slice to a merged PR. It does **not** need `project-init` to have run: on a project
with no plan documents the scope comes from what the user described at `start`, and SCOPE is
the gate that pins it down. Use `project-init` only when what to build has not been decided.

## Routing

**`status` (or no arguments):** execute INLINE — read `.lifecycle-state.json` and display the status table directly. Do NOT launch an agent. See "Status display" section below.

This skill's directory (its reference files live here) — resolved at runtime: !`echo ${CLAUDE_SKILL_DIR}`

The plugin's scripts directory — resolved at runtime: !`echo ${CLAUDE_PLUGIN_ROOT}/scripts`

**Both paths must be substituted into the agent prompt as literal absolute paths.** Reference
files are read as raw bytes: a `${CLAUDE_PLUGIN_ROOT}` written inside `steps.md` arrives at the
model unexpanded and runs as `bash "/scripts/detect-project.sh"`, which does not exist.

**`skip-compact`:** execute INLINE. Do NOT launch an agent — the compact gate blocks agent
launches, and this command exists to lift that block, so routing it through an agent means the
only way out of the gate is itself gated.

Write the state with `jq` through Bash, which is the one tool the compact gate does not match:

```
jq '.awaitingCompact = false
    | .compactSkippedAt = (now | todate)
    | .compactSkippedBefore = (.currentStep // "unknown")' .lifecycle-state.json > .lifecycle-state.json.tmp \
  && mv .lifecycle-state.json.tmp .lifecycle-state.json
```

This is the single exception to the "always write state with the Write tool" rule below, and it
exists only because `Write` is gated too. Run it only when the user asked for it in so many
words. Then tell them the gate is lifted and which step it was lifted before.

**All other commands** (`start`, `adopt`, `next`, `advance`, `complete`, `recover`): launch `Agent(general-purpose)` with the prompt below. Replace `SKILL_DIR` and `SCRIPTS_DIR_LITERAL` with the absolute paths printed just above:

```
Read these files in order:
1. SKILL_DIR/references/state-schema.md — state file structure
2. SKILL_DIR/references/project-config.md — the project's commands and plan location
3. SKILL_DIR/references/steps.md — find the section for the CURRENT step only

SCRIPTS_DIR is SCRIPTS_DIR_LITERAL. Wherever steps.md says SCRIPTS_DIR, use that path.

On `start`, do things in this order and no other: git preflight, then ADOPT if
`.bergant-workflow.json` is missing, then the task branch, then write the state file with
`awaitingCompact: true`. Writing that flag first blocks the agent that ADOPT needs.

Before anything else: read `.bergant-workflow.json` at the project root if it exists — it holds
the commands and `planGlob` that rules 6 and 8 depend on. If it does NOT exist, the project has
not been adopted: run the ADOPT section of steps.md first, whatever the requested command was.

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
10. When a task is completed, tick its checkbox in the corresponding plan file (the one `planGlob` matched).
11. **Live checklist, if the session has one.** If a checklist tool such as `TodoWrite` is
    available, mirror the step statuses into it so progress renders in the UI. It is a mirror,
    never the record — `.lifecycle-state.json` is the record, and `status` reads from it. Some
    builds do not expose the tool at all; when it is missing, skip this silently.

When you hit a user gate (STOP HERE), return the gate message. Return a concise summary of what was done and what the user needs to do next.

IMPORTANT: When writing or updating .lifecycle-state.json, ALWAYS use the Write tool — NEVER use Bash with cat/heredoc/echo redirect. Heredoc commands trigger permission prompts. The sole exception is `skip-compact`, documented above: `Write` is blocked by the very gate that command lifts.
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
| `next` | Read the plan files matched by `planGlob` (default `docs/plan/slice-*.md`), take the lowest-numbered file whose `Status:` line is not `done`, find its first unticked `- [ ]` task, run `start` on it. With `planGlob: null` there is nothing to pick up — say so and ask the user what to work on. |

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
