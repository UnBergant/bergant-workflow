---
name: project-init
description: Framework for creating project documentation from specs — reviews, research, architecture, planning, task decomposition into slices, and optional Jira sync. Triggers on "storm the spec", "analyze spec", "project init", "init project from spec", "проанализируй ТЗ", "разбери ТЗ", "создай документацию по ТЗ", or when user wants to turn a spec into structured project documentation. Also use when user asks to "break down a spec", "create PRD from spec", "plan implementation from requirements", or any workflow that converts a specification into actionable project docs with phases.
user-invocable: true
disable-model-invocation: false
allowed-tools: Agent, Read, Write, Edit, Bash, Glob, Grep
argument-hint: "[start <spec-file> [--from <phase>]|status|complete <phase>|recover]"
---

# Project Init

## Routing

**`status` (or no arguments):** execute INLINE — read `docs/spec-state.json` and display the phase table. Do NOT launch an agent. See "Status Display" below.

This skill's directory (its reference files live here) — resolved at runtime: !`echo ${CLAUDE_SKILL_DIR}`

**All other commands** (`start`, `complete`, `recover`): launch `Agent(general-purpose)` with the prompt below. Replace `SKILL_DIR` with the absolute path printed just above:

```
Read the project-init skill:
- Commands and rules: SKILL_DIR/SKILL.md (from "## Agent Instructions")
- Phase execution details: SKILL_DIR/references/phases.md (read ONLY the active phase section)

Execute command: $ARGUMENTS
State file: docs/spec-state.json
Project root: $CWD

Read existing docs/ artifacts for context before acting.
Follow all instructions. When you hit a user gate, return findings, options, and what needs discussion. Be concise.
```

If the agent returns an error, display it without re-running.

## Status Display

Read `docs/spec-state.json`. If missing: "No active spec analysis. Use `/bergant-workflow:project-init start <spec-file>` to begin."

Display formatted table:
- Each phase with status (pending, in_progress, completed)
- Current phase highlighted
- User gates marked
- Next action needed

---

## Agent Instructions

You manage the spec-to-documentation framework. State persists in `docs/spec-state.json`.

**Core principle:** Be interactive. Present options, trade-offs, recommendations. Ask the user to choose. Never make significant decisions silently.

**Advisory role:** Act as a **senior product manager** during PRD and a **senior architect** during ARCHITECTURE. Don't just document what the user said — analyze their needs deeper, suggest improvements they haven't considered, identify blind spots, and proactively propose solutions. Guide the user like a seasoned expert who's built similar systems before.

**Context management:** After completing any heavy phase, suggest `/compact` to free context. State and docs are persisted — nothing is lost.

**Graceful degradation:** Some phases use optional integrations (WebSearch, `/toxic-opinion`, Jira MCP). If a tool or skill is unavailable, skip that step, note it was skipped in the output docs, and continue. Never block a phase on a missing optional tool.

## Commands

### `start <spec> [--from <phase>]` — Initialize

`<spec>` can be: file path, inline text, or nothing (will ask).
`--from <phase>` optionally starts from a later phase (case-insensitive). Use when the user already has artifacts for earlier phases.

1. Check if `docs/spec-state.json` exists with incomplete phases. If so, warn and ask to override.
2. Read the spec:
   - File path → Read tool
   - Inline text → use as-is
   - Nothing provided → ask user to provide spec
3. If `--from` is specified:
   - Map required docs per phase: PRD needs `docs/REQUIREMENTS.md`; ARCHITECTURE needs REQUIREMENTS + `docs/prd.md`; PLANNING needs all three; etc.
   - Verify the required docs exist for all prior phases
   - If docs are missing, warn and ask user to provide them or start from the beginning
   - Mark all prior phases as `completed` (with note: "pre-existing")
4. `mkdir -p docs/plan`
5. Create `docs/spec-state.json`:

```json
{
  "version": 2,
  "spec": "<source>",
  "project": "<inferred name>",
  "startedAt": "<ISO>",
  "currentPhase": "INPUT_VALIDATION",
  "config": {},
  "phases": {
    "INPUT_VALIDATION": { "status": "in_progress", "gate": "user", "gateDescription": "Confirm spec is sufficient" },
    "PRD": { "status": "pending", "gate": "user", "gateDescription": "Approve product requirements" },
    "ARCHITECTURE": { "status": "pending", "gate": "user", "gateDescription": "Approve architecture and tech decisions" },
    "PLANNING": { "status": "pending", "gate": "user", "gateDescription": "Approve development phases" },
    "DECOMPOSITION": { "status": "pending", "gate": "user", "gateDescription": "Approve task slices (optional Jira sync after)" },
    "FINALIZE": { "status": "pending", "gate": "auto" }
  }
}
```

The `config` object stores runtime settings acquired during phases (e.g., `jiraCloudId`, `jiraProjectKey`).

6. Execute the starting phase immediately (see `references/phases.md`).

### `complete <phase>` — Confirm user gate

Phase name matching is **case-insensitive** (`prd`, `PRD`, `Prd` all work).

1. Read state. Verify `<phase>` matches `currentPhase`.
2. If the completed phase's docs contain open questions or assumptions, ask the user whether any need updating before proceeding. Update docs with their answers.
3. Mark phase `completed` with timestamp.
4. Advance `currentPhase` to next phase, set it `in_progress`.
5. Save state.
6. Execute the next phase (see `references/phases.md`).
7. If next phase has user gate → present findings and STOP.

### `recover` — Reconstruct state from existing files

1. Scan `docs/` for: REQUIREMENTS.md, prd.md, architecture.md, plan/phase-*.md.
2. Infer which phases are complete based on file existence and content.
3. Present findings as a table, ask user to confirm.
4. On confirmation: write `docs/spec-state.json`.

---

## Critical Rules

1. **Never skip phases** unless `--from` is used at start. Order: INPUT_VALIDATION → PRD → ARCHITECTURE → PLANNING → DECOMPOSITION → FINALIZE.
2. **Never advance past user gates** without explicit `/bergant-workflow:project-init complete <phase>`.
3. **Always update `docs/spec-state.json`** after every phase transition. State file is source of truth.
4. **Always read state file and existing docs** before acting. Never rely on conversation history.
5. **Sub-agents for heavy work.** Web research, toxic opinion, Jira ops — always via Agent to protect context.
6. **Jira only via agents.** Never call `mcp__atlassian__*` in main context. Use jira-ops skill patterns.
7. **Interactive by default.** Multiple options → present trade-offs, ask user. Don't decide silently.
8. **MVP mindset.** Core flow first, polish last. Flag post-MVP ideas but don't over-plan them.
9. **Suggest `/compact`** after heavy phases (PRD, ARCHITECTURE, PLANNING, DECOMPOSITION).
10. **Never overwrite docs** without asking. If updating, show diff or ask permission first.
11. **Optional integrations are opt-in.** Always ask before web research or toxic-opinion. If tool unavailable, skip and note in docs.
12. **Files are the contract.** All decisions must be captured in docs before completing a phase. Conversation is ephemeral, files persist.
13. **Graceful degradation.** If an optional tool is unavailable, skip that step and continue — never block the workflow.
14. **Always use current LTS/stable versions.** When choosing technologies, always pick the latest LTS (for Node.js, PostgreSQL) or latest stable release (for React, frameworks, libraries). Never use outdated versions for new projects — verify current versions via web search or documentation before committing to a version number.

## State File

`docs/spec-state.json` — in the project's `docs/` directory.

- `version` — schema version (current: 2) for future migration compatibility
- `config` — runtime settings acquired during phases (Jira Cloud ID, project key, etc.)
- `phases` — status of each phase with gate info

## Optional dependencies

These power specific phases. The first time a phase needs one and it's missing, offer the user a
**one-time choice — install it now or skip** (note the skip in the output docs). Never hard-block
a phase on a missing optional tool.

| Dependency | Phase | If missing |
|------------|-------|-----------|
| `toxic-opinion` skill + Codex CLI | second opinion in every phase | offer `npm i -g @openai/codex`, else skip with note |
| WebSearch | PRD market / legal research | skip, note in docs |
| Jira MCP (`mcp__atlassian__*`) | DECOMPOSITION → optional Jira sync | user declines or MCP missing → skip Jira; slices stay in `docs/slices/` |
| design-agents + interface-design / Vercel skills | ARCHITECTURE design system | skip the design-system substeps, note in docs |
