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
- **Run `/toxic-opinion` for a second opinion on the scope** (default ON). Frame the Codex prompt around the task scope, key decisions, and potential risks. Present Codex findings alongside your own. If the toxic-opinion skill or Codex CLI is unavailable, offer the user a one-time choice — install it (`npm i -g @openai/codex`) or skip — and note the skip. Never hard-block on it.
- **STOP HERE.** Display requirements, AI perspective, Codex second opinion, and: `When ready: /bergant-workflow:lifecycle complete SCOPE`
- Do NOT proceed to PLAN until user confirms.

**On `/bergant-workflow:lifecycle complete SCOPE` (MANDATORY state writes — these are standard fields, see `state-schema.md`):**

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
- **STOP HERE.** `When done: /bergant-workflow:lifecycle complete VERIFY`
- Do NOT proceed further.

## TEST

- Write unit tests (Vitest) for new business logic.
- Write E2E tests (Playwright) if UI changed.
- Run `npm run test` (and `npm run test:e2e` if applicable).
- Mark TEST completed, advance.

## REVIEW (gate: user)

- **Pre-commit safety check (BEFORE staging — do not skip).** Make sure no secrets or
  transient files are about to be committed:
  - Inspect what would be staged: `git status --porcelain` and `git diff --cached --name-only`.
  - **Block-list:** `.env`, `.env.*` (except `.env.example`), `*.key`, `*.pem`, `secrets/`,
    `.lifecycle-state.json`, `docs/spec-state.json`, `.claude/`, and any file containing
    obvious credentials (API keys, tokens, connection strings, private keys).
  - For each match: verify it is listed in `.gitignore`. If not → add it to `.gitignore`.
    If it is already tracked → `git rm --cached <file>` so it stops being committed.
  - Scan the staged diff for inline secrets (high-entropy strings, `password=`, `Bearer `,
    `postgres://...:...@`). If found → STOP, tell the user, do NOT commit until resolved.
  - Only proceed to commit once the working tree is clean of secrets/temp files.
- **Then: commit all changes.** Submitting for review === commit. Stage all changed files and create a commit on the feature branch. Do NOT push.
- Launch review Agent AND run `/toxic-review` in parallel (default ON). If the toxic-review skill or Codex CLI is unavailable, offer to install it once or proceed with the single review Agent only — note which was used.
- toxic-review reviews the branch diff — pass base branch as argument (e.g., `/toxic-review master`).
- Present findings: MUST FIX / SHOULD FIX / NIT.
- **STOP.** Ask user which fixes to apply.

**On `/bergant-workflow:lifecycle complete REVIEW`:**
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

**On `/bergant-workflow:lifecycle complete CLOSE`:**
1. Merge PR (use GitHub MCP `merge_pull_request`, not gh CLI). Delete remote branch.
2. `git checkout master && git pull`.
3. `git branch -d <branch>`.
4. `rm .lifecycle-state.json`.
5. **Clean up TaskList:** Delete all lifecycle tasks (`[CONTEXT_CHECK]`, `[SCOPE]`, `[PLAN]`, `[COMPONENTS]`, `[IMPLEMENT]`, `[VERIFY]`, `[TEST]`, `[REVIEW]`, `[DOCUMENT]`, `[CLOSE]`) via `TaskUpdate` with `status: "deleted"`.
6. Update task status in `docs/plan/slice-*.md` (change ⏳ to ✅).
7. Suggest: `/bergant-workflow:lifecycle next`.
