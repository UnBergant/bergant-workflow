# Lifecycle Step Execution

Read only the section for the current step. Do not load the entire file into context.

## CONTEXT_CHECK

- Exists solely to enforce context cleanup before real work begins.
- On `start`: state file created with `awaitingCompact: true`. PreToolUse(Agent) hook blocks agent launches.
- **Create task branch** from master: `git checkout master && git pull && git checkout -b <task-key-lowercase>`. Update `"branch"` in state.
- After `/compact`: SessionStart(compact) hook clears `awaitingCompact`.
- On resume after compact: mark CONTEXT_CHECK completed, advance to SCOPE.
  - If SCOPE already `"completed"` (via `--skip-scope`): skip to PLAN and begin executing.
  - If SCOPE `"pending"`: advance to SCOPE (user gate — present requirements and STOP).

## SCOPE (gate: user)

- Read task description from `docs/plan/slice-*.md` (find the relevant slice file for this task).
- Present: summary, scope, acceptance criteria.
- Provide AI perspective: challenges, ambiguities, questions.
- **MANDATORY: Run `/toxic-opinion` for second opinion on the scope.** Frame the Codex prompt around the task scope, key decisions, and potential risks. Present Codex findings alongside your own.
- **STOP HERE.** Display requirements, AI perspective, Codex second opinion, and: `When ready: /lifecycle complete SCOPE`
- Do NOT proceed to PLAN until user confirms.

**On `/lifecycle complete SCOPE` (MANDATORY state writes — these are standard fields, see `state-schema.md`):**

Write to `.lifecycle-state.json`:
- `scopeApprovedAt`: current ISO timestamp
- `codexOpinionIncorporated`: `true` if `/toxic-opinion` ran AND its findings merged into the approved scope; `false` if Codex timed out or user rejected its input
- `codexFindings`: array of short snake_case semantic tags (≤4 words each) distilled from Codex's second opinion — one tag per implementable decision (e.g., `"schema_enum_fix_required"`, `"split_transactions"`, `"pii_redaction"`). These are anchors for post-compact context recovery in PLAN.
- `scopeNotes.approvedScope`: bullet-list array of concrete scope items the user confirmed — becomes the source of truth for PLAN and IMPLEMENT.
- `steps.SCOPE.status`: `"completed"`

Then advance `currentStep` to `"PLAN"` and set `steps.PLAN.status` to `"in_progress"`.

## PLAN

- Read task description from `docs/plan/slice-*.md`.
- Explore related code via Agent(Explore).
- **Component inventory (MANDATORY for UI tasks):** For each component: new or existing? tokens needed? variants/states? Can reuse existing tokens?
- Present plan to user. When approved:
  - Update TaskList: replace placeholder `[IMPLEMENT]` task with individual subtasks `[IMPLEMENT] S1: <title>`, etc.
  - Save component inventory to `"components"` array in COMPONENTS step.
- **Set `"awaitingCompact": true`**.
- Display: `✅ PLAN completed. 🧹 Run /compact before continuing.`
- Do NOT start COMPONENTS.

## COMPONENTS (gate: user)

**Skip condition:** If task has NO UI components, auto-complete and advance to IMPLEMENT.

**For UI tasks:**
1. Read component inventory from state.
2. For each NEW component:
   a. Check/generate design tokens.
   b. Build component (shadcn/ui primitives, all states, accessibility, responsive).
   c. Create `.stories.tsx` (story per variant, per state, responsive).
   d. Update status to `"completed"` in state.
3. For EXISTING components: update + update story. Mark `"completed"`.
4. Run Storybook build.
5. **STOP HERE.** List new/updated components, tokens. Ask user to review in Storybook.
6. Do NOT proceed to IMPLEMENT until approved.

## IMPLEMENT

- For each subtask in order:
  - Update subtask status to `in_progress`.
  - Launch Agent(general-purpose) with focused instructions.
  - On return: update subtask to `completed`.
- When all done: `npm run build` + `npm run lint`.
- If pass: mark IMPLEMENT completed, advance.
- If fail: fix, re-check.

## VERIFY (gate: user)

- Run: `npm run build`, `npm run lint`.
- Display test plan: task-specific manual checks (user-facing checklist, not developer checklist).
- **STOP HERE.** `When done: /lifecycle complete VERIFY`
- Do NOT proceed further.

## TEST

- Write unit tests (Vitest) for new business logic.
- Write E2E tests (Playwright) if UI changed.
- Run `npm run test` (and `npm run test:e2e` if applicable).
- Mark TEST completed, advance.

## REVIEW (gate: user)

- **First: commit all changes.** Submitting for review === commit. Stage all changed files and create a commit on the feature branch. Do NOT push.
- Launch review Agent AND run `/toxic-review` in parallel (MANDATORY — never skip toxic-review).
- toxic-review reviews the branch diff — pass base branch as argument (e.g., `/toxic-review master`).
- Present findings: MUST FIX / SHOULD FIX / NIT.
- **STOP.** Ask user which fixes to apply.

**On `/lifecycle complete REVIEW`:**
- Apply fixes, commit, build/lint, mark completed, advance.

## DOCUMENT

- Update `MEMORY.md` with decisions and learnings (if any).
- Check `design-issues.md` for items to close.
- Update `CLAUDE.md`/`AGENTS.md` if project structure changed.
- Mark completed, advance.

## CLOSE (gate: user)

**Phase 1 — Create PR:**
- Run final: `npm run build`, `npm run test`.
- Commit remaining changes (if any).
- Push branch to remote.
- Create PR (use GitHub MCP `create_pull_request`, not gh CLI).
- **STOP.** Show PR link. Ask user to review.

**On `/lifecycle complete CLOSE`:**
1. Merge PR (use GitHub MCP `merge_pull_request`, not gh CLI). Delete remote branch.
2. `git checkout master && git pull`.
3. `git branch -d <branch>`.
4. `rm .lifecycle-state.json`.
5. **Clean up TaskList:** Delete all lifecycle tasks (`[CONTEXT_CHECK]`, `[SCOPE]`, `[PLAN]`, `[COMPONENTS]`, `[IMPLEMENT]`, `[VERIFY]`, `[TEST]`, `[REVIEW]`, `[DOCUMENT]`, `[CLOSE]`) via `TaskUpdate` with `status: "deleted"`.
6. Update task status in `docs/plan/slice-*.md` (change ⏳ to ✅).
7. Suggest: `/lifecycle next`.
