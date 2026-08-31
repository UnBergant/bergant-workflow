# Lifecycle Step Execution

Read only the section for the current step. Do not load the entire file into context.

## ADOPT (runs once per project, before CONTEXT_CHECK)

Skip entirely if `.bergant-workflow.json` already exists. Otherwise the project has never been
through this plugin, and guessing how it builds and where its plan lives is how a tool wrecks
someone's repository. Look first, then ask once.

1. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-project.sh"`. It prints JSON and never fails.
2. **Plan documents**, in order:
   - `nativePlan: true` → use `docs/plan/slice-*.md`, say so, ask nothing.
   - exactly one candidate → propose it: "Is `<path>` the plan I should work from?"
   - several → list them and ask which, or none.
   - none → say that plainly and offer to work from task descriptions instead.
   In every branch the user may answer "no plan" — that is a normal project, not a broken one.
3. **Commands**: show what was detected (`build`, `lint`, `test`, `e2e`) and what came back
   empty. Ask the user to correct or fill them. Never invent one: a project with no lint
   command has no lint command, and `VERIFY` will skip that check and say it skipped it.
4. Write `.bergant-workflow.json` at the project root and **commit it** — it describes the
   project, not the run, and the next person benefits from it. Then continue to CONTEXT_CHECK.

**STOP HERE** until the user has confirmed both halves. This is a user gate in everything but
name: everything the lifecycle later runs against their code comes from these two answers.

## CONTEXT_CHECK

- Exists solely to enforce context cleanup before real work begins.
- On `start`: state file created with `awaitingCompact: true`. PreToolUse(Agent) hook blocks agent launches.
- **Git preflight — run before touching anything.** Never assume the branch name, never move
  someone else's work:
  1. Find the real default branch, do not assume `master`:
     `git symbolic-ref --quiet --short refs/remotes/origin/HEAD | sed 's|^origin/||'`.
     If that is empty, try `main`, then `master`, then ask the user. Record it as `"baseBranch"`.
  2. `git status --porcelain`. If anything comes back, **STOP and ask the user** what to do with
     it. Do NOT `git stash`, `git checkout -f`, `git clean`, or commit it — those are the user's
     changes and hiding them is worse than stopping.
  3. `git rev-parse --git-dir` and check for `rebase-merge`, `rebase-apply`, `MERGE_HEAD`,
     `CHERRY_PICK_HEAD`, `BISECT_LOG`. If any exist, an operation is in progress → **STOP.**
  4. If `HEAD` is detached, **STOP** and say so.
- **Create task branch** only once the preflight is clean:
  `git checkout <baseBranch> && git pull --ff-only && git checkout -b <task-key-lowercase>`.
  Update `"branch"` and `"baseBranch"` in state. `--ff-only` so a diverged local base fails
  loudly instead of producing a merge.
- After `/compact`: SessionStart(compact) hook clears `awaitingCompact`.
- The gate blocks agent launches and edit tools while the flag is set; `Bash` is deliberately
  left alone so the user can still look around while deciding. If the user explicitly says to
  continue without compacting, run `/bergant-workflow:lifecycle skip-compact`: set
  `awaitingCompact: false`, `compactSkippedAt` to the current ISO timestamp, and
  `compactSkippedBefore` to the step. Never do this without being asked.
- On resume after compact: mark CONTEXT_CHECK completed, advance to SCOPE.
  - If SCOPE already `"completed"` (via `--skip-scope`): skip to PLAN and begin executing.
  - If SCOPE `"pending"`: advance to SCOPE (user gate — present requirements and STOP).

## SCOPE (gate: user)

- Read task description from `docs/plan/slice-*.md` (find the relevant slice file for this task).
- Present: summary, scope, acceptance criteria.
- Provide AI perspective: challenges, ambiguities, questions.
- **Run `/toxic-opinion` for a second opinion on the scope** (default ON). Frame the Codex prompt around the task scope, key decisions, and potential risks. Present Codex findings alongside your own. If no second-opinion skill is available, note the skip and continue with your own analysis. Never hard-block on it.
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
  - Record the subtasks in `steps.IMPLEMENT.subtasks` in the state file — that is the record, and `/bergant-workflow:lifecycle status` renders it. If a checklist tool such as `TodoWrite` is available, mirror them there too.
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
- When all done: run `commands.build` and `commands.lint` from `.bergant-workflow.json`. A `null` command is skipped, and the skip is reported.
- If pass: mark IMPLEMENT completed, advance.
- If fail: fix, re-check.

## VERIFY (gate: user)

- Run `commands.build` and `commands.lint`. Report any that are `null` as not configured rather than substituting something.
- Display test plan: task-specific manual checks (user-facing checklist, not developer checklist).
- **STOP HERE.** `When done: /bergant-workflow:lifecycle complete VERIFY`
- Do NOT proceed further.

## TEST

- Write unit tests for new business logic, in whatever the project already uses — infer the framework from existing tests, never introduce a new one inside a slice.
- Write E2E tests if UI changed and the project has an E2E setup.
- Run `commands.test` (and `commands.e2e` if the slice touched UI and one is configured).
- Mark TEST completed, advance.

**Skip condition:** If the slice added no business logic and touched no UI — docs, config,
or a pure refactor already covered by existing tests — auto-complete TEST and write the
reason into `steps.TEST.skipReason`. Never skip it silently: the `Stop` hook refuses to end
the turn once REVIEW starts while TEST is unfinished, and a slice that shipped logic with an
empty `skipReason` means tests were dropped, not waived.

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
- **Then: commit the task's own files.** Submitting for review === commit. Stage files by
  explicit path — the ones this slice created or changed. Never `git add -A`, `git add .`, or
  `git commit -a`: anything else in the tree belongs to the user, and the preflight promised not
  to touch it. If `git status --porcelain` shows changes you cannot attribute to this task,
  **STOP and ask** rather than sweeping them into the commit. Do NOT push.
- Launch review Agent AND, if a dual-review skill such as `/toxic-review` is available, run it in parallel (default ON). If not available, proceed with the single review Agent only — note which was used.
- toxic-review reviews the branch diff — pass the recorded `baseBranch` as argument (e.g., `/toxic-review main`).
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
- Run final: `commands.build`, `commands.test`.
- Commit remaining changes (if any).
- Push branch to remote.
- Create PR: `gh pr create --base <base> --title "..." --body "..."`. If `gh` is unavailable,
  fall back to GitHub MCP `create_pull_request`.
- **STOP.** Show PR link. Ask user to review.

**On `/bergant-workflow:lifecycle complete CLOSE`:**
1. Merge PR: `gh pr merge <number> --squash --delete-branch`. If `gh` is unavailable, fall back
   to GitHub MCP `merge_pull_request` and delete the remote branch.
2. `git checkout <baseBranch> && git pull --ff-only`.
3. `git branch -d <branch>` — the safe form only. Never `-D`: if git refuses because the branch
   is not merged, that is information, not an obstacle. Report it and stop.
4. `rm .lifecycle-state.json`.
5. Mark the slice done in `docs/plan/slice-*.md`: change the slice's own status line from
   `Status: in progress` to `Status: done`. Individual task checkboxes are updated as they are
   completed, throughout — not here.
6. Suggest: `/bergant-workflow:lifecycle next`.
