---
name: lifecycle
description: Orchestrate feature lifecycle — track steps, enforce gates, dispatch sub-agents. Use when starting a new task, checking lifecycle status, or advancing to the next step.
user-invocable: true
disable-model-invocation: false
allowed-tools: Agent, Read
argument-hint: "[start|next|status|advance|complete <step>]"
---

# Lifecycle Orchestrator

## Routing

**`status` (or no arguments):** execute INLINE — read `.lifecycle-state.json` and display the status table directly. Do NOT launch an agent. See "Status display" section below.

**All other commands** (`start`, `next`, `advance`, `complete`, `recover`): launch `Agent(general-purpose)` with this prompt:

```
Read these files in order:
1. ~/.claude/skills/lifecycle/references/state-schema.md — state file structure
2. ~/.claude/skills/lifecycle/references/steps.md — find the section for the CURRENT step only

Execute lifecycle command: $ARGUMENTS
State file: .lifecycle-state.json

Critical rules:
1. NEVER skip a step. Order: CONTEXT_CHECK → SCOPE → PLAN → COMPONENTS → IMPLEMENT → VERIFY → TEST → REVIEW → DOCUMENT → CLOSE.
2. NEVER advance past a user gate without `/lifecycle complete <step>`.
3. Always update state file after every transition.
4. Always read state file before any action.
5. Use Agent tool for heavy work (IMPLEMENT subtasks, REVIEW).
6. Task context comes from local files in `docs/plan/slice-*.md` — do NOT use Jira MCP. Read the relevant slice file to understand task scope and dependencies.
7. GitHub operations via MCP tools (mcp__github__*), not gh CLI.
8. **Sync TaskList with step status.** When a step changes status in the state file, find the matching TaskList task by its `[STEP_NAME]` prefix and update it: `in_progress` when step starts, `completed` when step finishes. Use TaskList to find the task ID, then TaskUpdate to change status.
9. When a task is completed, update its status in the corresponding `docs/plan/slice-*.md` file (change ⏳ to ✅).

When you hit a user gate (STOP HERE), return the gate message. Return a concise summary of what was done and what the user needs to do next.

IMPORTANT: When writing or updating .lifecycle-state.json, ALWAYS use the Write tool — NEVER use Bash with cat/heredoc/echo redirect. Heredoc commands trigger permission prompts.
```

If the agent returns an error, display it to the user without re-running.

## Status display

Read `.lifecycle-state.json`. If no file exists, say "No active lifecycle. Use `/lifecycle start <task-name>` to begin."

Display a formatted table:
- Each step with status emoji (⏳ pending, 🔄 in_progress, ✅ completed)
- Current step highlighted
- User gates marked with 🚧
- Subtask progress for IMPLEMENT step
- What the next action should be

## Commands (summary)

| Command | Action |
|---------|--------|
| `start <task>` | Initialize lifecycle, create state + TaskList, set `awaitingCompact: true`. Supports `--skip-scope`. |
| `advance` | Move to next step (validates current is completed, respects gates). |
| `complete <step>` | User confirms a gate. Marks step completed, advances. |
| `recover` | Reconstruct state from git/build/tests when state file is lost. |
| `next` | Read `docs/plan/slice-*.md` files, find first ⏳ task in the lowest incomplete slice, run `start` on it. |

## State File Location

`.lifecycle-state.json` — in the project root. This file is gitignored.
