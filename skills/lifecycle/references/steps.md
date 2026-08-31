# Lifecycle Step Execution

Read only the section for the current step. Do not load the entire file into context.

## ADOPT (runs once per project, at the start of CONTEXT_CHECK)

Skip entirely if `.bergant-workflow.json` exists AND has a `commands` object. If it exists but
is malformed or missing `commands`, say so and adopt again. Otherwise the project has never
been through this plugin, and guessing how it builds and where its plan lives is how a tool
wrecks someone's repository. Look first, then ask once.

**Order matters: run the git preflight from CONTEXT_CHECK below BEFORE writing anything.**
Adoption writes a file and offers to commit it, and doing that on a dirty tree, a detached
HEAD, or a half-finished rebase is exactly the surgery the preflight exists to prevent.

1. Run `bash "SCRIPTS_DIR/detect-project.sh"` — the absolute path given in the agent prompt,
   not a literal `SCRIPTS_DIR`. It prints JSON and never fails.
2. **Plan documents**, in order:
   - `nativePlan: true` → use `docs/plan/slice-*.md`, say so, ask nothing.
   - exactly one candidate → propose it: "Is `<path>` the plan I should work from?"
   - several → list them and ask which, or none.
   - none → say that plainly and offer to work from task descriptions instead.
   In every branch the user may answer "no plan" — that is a normal project, not a broken one,
   and it records as `"planGlob": null`.
3. **Commands**: show what was detected (`build`, `lint`, `test`, `e2e`) and what came back
   empty. Ask the user to correct or fill them. Never invent one: a project with no lint
   command has no lint command, and `VERIFY` will skip that check and say it skipped it.
   - **Empty repository?** If every command is `null` and there is no manifest yet — the
     `project-init` path, where the code does not exist yet — say so, record what you have, and
     set `"adoptedFrom": "empty"`. The first later step that finds a manifest re-runs ADOPT
     rather than reporting "not configured" for the rest of the project's life.
4. **STOP HERE** until the user has confirmed both halves. This is a user gate in everything but
   name: everything the lifecycle later runs against their code comes from these two answers.
5. Only then write `.bergant-workflow.json` at the project root, and commit it by exact path,
   never with `-A` or `.`:
   ```
   git add .bergant-workflow.json && git commit -m "chore: adopt bergant-workflow"
   ```
   If the tree was dirty and the user chose to continue anyway, do **not** commit — write the
   file, say it is uncommitted, and let them commit it with their own work. Then continue with
   the rest of CONTEXT_CHECK.

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
  `git checkout <baseBranch> && git pull --ff-only && git checkout -b <branch>`, where
  `<branch>` is the task name lowercased with every run of non-alphanumeric characters replaced
  by a single `-`, trimmed, cut to 50 characters — `lifecycle start "Add user login"` branches
  `add-user-login`. Do not improvise another scheme: the name is recorded in state and reused
  at REVIEW and CLOSE.
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

- Read the task description from the plan file matched by `planGlob`. With `planGlob: null`, the scope is what the user said at `start` — write it down and confirm it here.
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

- Read the task description from the plan file matched by `planGlob`, or the scope approved at SCOPE when there is none.
- Explore related code via Agent(Explore).
- **Component inventory (MANDATORY for UI tasks):** For each component: new or existing? tokens needed? variants/states? Can reuse existing tokens?
- Present plan to user. When approved:
  - Record the subtasks in `steps.IMPLEMENT.subtasks` in the state file — that is the record, and `/bergant-workflow:lifecycle status` renders it. If a checklist tool such as `TodoWrite` is available, mirror them there too.
  - Save component inventory to `"components"` array in COMPONENTS step.
- **Set `"awaitingCompact": true`**.
- Display: `✅ PLAN completed. 🧹 Run /compact before continuing.`
- Do NOT start COMPONENTS.

## COMPONENTS (gate: user)

**Skip condition:** If the task has no UI components, auto-complete this gate and advance to
IMPLEMENT, recording why in `steps.COMPONENTS.skipReason`. This is the one user gate the model
may close on its own, and only for this reason — say out loud that it was skipped and why.

**For UI tasks:**
1. Read component inventory from state.
2. For each NEW component:
   a. Check/generate design tokens.
   b. Build the component in whatever the project already uses — read a neighbouring component
      first. Do not introduce a primitives library, a styling approach or a story format the
      repository does not already have. Cover all states, accessibility and responsiveness.
   c. If the project has a component workbench (a `storybook` entry in
      `.bergant-workflow.json`, or existing story files), add stories matching the format
      already in use — one per variant, per state, responsive. If it has none, skip this and
      say so; do not scaffold one inside a slice.
   d. Update status to `"completed"` in state.
3. For EXISTING components: update + update story. Mark `"completed"`.
4. Run the workbench build if `commands.storybook` is configured. If it is not, skip and say so.
5. **STOP HERE.** List new and updated components and tokens, and say where the user can look
   at them — the workbench if there is one, the running app otherwise.
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

Update what the project already keeps. **Do not create a documentation file the repository does
not have** — a `MEMORY.md` invented here is a file the user never asked for, committed at CLOSE.

- If `MEMORY.md`, `design-issues.md` or a similar running log exists, add what this slice
  decided or closed.
- If `CLAUDE.md` or `AGENTS.md` exists and the project structure changed, update it.
- If none of them exist, say that there was nothing to update and move on.
- Mark completed, advance.

## RECOVER (not a step — repairs a lost state file)

Runs when `.lifecycle-state.json` is missing or unreadable but work is clearly under way.
Reconstruct conservatively: **when the evidence is ambiguous, mark the step NOT completed.** An
over-generous reconstruction silently retires the gates for the rest of the run, which is worse
than repeating a step.

1. Read `.bergant-workflow.json`. Without it, run ADOPT first.
2. Establish the branch (`git rev-parse --abbrev-ref HEAD`) and its base
   (`git symbolic-ref --quiet --short refs/remotes/origin/HEAD`).
3. Infer only what git can show, and say what you inferred from what:
   - commits on the branch → CONTEXT_CHECK completed.
   - the slice file named in the branch, or the user's description → the task.
   - test files touched by those commits → TEST may be completed; nothing else implies it.
4. **Mark every user gate (SCOPE, COMPONENTS, VERIFY, REVIEW, CLOSE) as `pending`.** An approval
   is a thing the user gave, and no artefact on disk proves it happened. Re-asking costs a
   sentence; assuming costs the guarantee.
5. Write the state file, show the user the reconstructed table, and ask them to correct it
   before continuing.

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
5. Mark the slice done in its plan file (the one `planGlob` matched). `project-init` writes
   that line as `Status: ⏳ pending`; change it to `Status: ✅ done`. If the file words it
   differently, match what is actually there rather than inventing a new form. Task checkboxes
   are ticked as they are completed, throughout — not here. **`next` finds the next slice by
   this line, so a slice never marked done is a slice the plugin returns to forever.**
6. Suggest: `/bergant-workflow:lifecycle next`.
