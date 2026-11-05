# Lifecycle Step Execution

Read only the section for the current step. Do not load the entire file into context.

## Project commands (used by every step that builds, lints or tests)

A repository can hold several projects — a Swift package in `recorder/`, a uv project in
`transcribe/`, a web app in `web/` — and every check runs against **all of them**, not only the
root. Never assemble the commands yourself and never run only `commands.*`:

- `bash "SCRIPTS_DIR/project-commands.sh" run <build|lint|test|e2e>` runs every project's
  command for that check, one after another from the repository root, keeps going after a
  failure, and ends with one `PASS` / `FAIL` / `SKIP` line per project. Exit 1 means at least
  one failed; exit 3 with `NOTHING RAN` means no project had the command, which is never
  "tests passed"; exit 2 means `.bergant-workflow.json` is broken. Report the summary as it is;
  a `SKIP … none` is a project with no such command.
- `bash "SCRIPTS_DIR/project-commands.sh" <kind>` prints the same plan as JSON without running
  it, and `… markdown` prints it for people.

Projects are rediscovered on every call: the root, every directory one or two levels down with
a manifest (`package.json`, `Package.swift`, `pyproject.toml`, `go.mod`, `Cargo.toml`), and every
path listed under `projects` in `.bergant-workflow.json`. A sub-project created since adoption
is therefore checked from the next step on, without editing the config. What the config says
is applied on top — see `project-config.md` for `commands`, `projects` and `exclude`.

**The shared list.** The same plan, written for people, lives in
`docs/bergant-workflow-commands.md`. It is regenerated, never edited by hand:
`bash "SCRIPTS_DIR/project-commands.sh" markdown > docs/bergant-workflow-commands.md`
(`mkdir -p docs` first). It is refreshed at ADOPT, after the task branch is created in
CONTEXT_CHECK, and before the final commit at CLOSE. If the repository has a `CLAUDE.md` or
`AGENTS.md` that does not mention the file yet, add one line to it once:
`Build, lint and test commands for every project: docs/bergant-workflow-commands.md.`

## ADOPT (runs once per project, at the start of CONTEXT_CHECK)

Skip entirely if `.bergant-workflow.json` exists AND has a `commands` object — unless it says
`"adoptedFrom": "empty"` and detection now finds a project, which is the re-adoption described
under "Empty repository?" below. If it holds only
`projects` (and maybe `exclude`), `project-init` started it: adopt, keeping those. If it is
malformed, say so and adopt again. Otherwise the project has never
been through this plugin, and guessing how it builds and where its plan lives is how a tool
wrecks someone's repository. Look first, then ask once.

**Order matters: run the git preflight from CONTEXT_CHECK below BEFORE writing anything.**
Adoption writes a file and offers to commit it, and doing that on a dirty tree, a detached
HEAD, or a half-finished rebase is exactly the surgery the preflight exists to prevent.

1. Run `bash "SCRIPTS_DIR/detect-project.sh"` — the absolute path given in the agent prompt,
   not a literal `SCRIPTS_DIR`. It prints JSON and never fails. `projects` lists every project
   it found, the root included when it has a manifest; `stack` and `commands` describe the root
   alone. If `.bergant-workflow.json` already exists without `commands` — `project-init` wrote
   only the planned layout — keep its `projects` and `exclude` and add to them, never replace.
2. **Plan documents**, in order:
   - `nativePlan: true` → use `docs/plan/slice-*.md`, say so, ask nothing.
   - exactly one candidate → propose it: "Is `<path>` the plan I should work from?"
   - several → list them and ask which, or none.
   - none → say that plainly and offer to work from task descriptions instead.
   In every branch the user may answer "no plan" — that is a normal project, not a broken one,
   and it records as `"planGlob": null`.
3. **Commands**: show the output of `bash "SCRIPTS_DIR/project-commands.sh" markdown` — every
   project with its `build`, `lint`, `test` and `e2e`, and what came back empty. Ask the user
   to correct or fill them. A correction for the root goes in `commands`, one for a
   sub-project in `projects.<path>` (`"lint": "..."` replaces, `null` disables, `"skip": true`
   leaves the project out), and a directory that is not a project of theirs goes in `exclude`.
   A project with a `note` has a second manifest whose commands only the user can give. Never
   invent one: a project with no lint command has no lint command, and `VERIFY` will skip that
   check and say it skipped it.
   - **No test command is the common case, not an edge case.** Most repositories have no tests
     at all, and not having to work out how to add them is a large part of why this exists. So
     do not record `null` and move on — make the offer, using `testSetup` from the detection
     output, which names a runner that fits the stack.

     The offer is per project. `testSetup` in the detection output is the root's; for a
     sub-project without a test command, name the runner its stack uses and record the answer
     under `projects.<path>` (`testSetupAccepted`, `testSetupDeclined`) — never at the root,
     or the runner gets installed in the wrong place.

     **Recommend, with the reason, in plain words.** The person reading may not know what the
     runner is or why they would want one, so say what it costs and what it buys:
     > "This project has no test command, so the TEST step would have nothing to run and every
     > slice would ship unverified. I'd suggest `<runner>` — it's what this stack normally uses.
     > It adds one dev dependency and a config file, and it goes in on the first slice that
     > needs it, in that branch, through the same review as the code. **My recommendation: yes.**
     > You can also give me the command you already use, or say not now."

     **Name the e2e runner too when `testSetup.e2e` is set.** A UI project's logic tests and its
     browser tests are two different decisions, and the second is where a front end actually
     breaks — mentioning only the unit runner drops half the offer:
     > "The project has a UI, so there's a second layer worth having: `<e2e>` drives a real
     > browser through the flows a unit test cannot see. Same terms — installed on the first
     > slice that needs it. It can be a separate yes or no."

     **When `testSetup.integration` is set, offer it as a third, optional layer, with its
     price.** For a Telegram bot, the part that breaks is the conversation, and only a real
     client exercises it:
     > "This looks like a Telegram bot. Unit tests cover your handlers — the functions — but not
     > the thing that actually breaks: the conversation. `<integration>` is a Telegram *client*
     > library: it signs in as an ordinary user account and messages your bot the way a person
     > would, so a test can send `/start`, read what comes back, tap a button and check the next
     > screen. That is the real way to test a bot, and here is the honest price: it needs a
     > second Telegram account and API credentials, it talks to Telegram's servers rather than a
     > local mock, it is slower, and it should not run in CI by default. Worth having, but only
     > if you want it — say no and the unit layer still stands on its own."
     Explain what the tool *is* in that much detail every time. The people who most need this
     offer are the ones who have never heard of the library, and "set up Telethon?" is not a
     question they can answer.
     Record it as `"integrationTest": "<tool>"` if accepted. Never set it up unasked. Credentials
     go in the environment, never in the repository — and the pre-commit secret scan at REVIEW
     treats a leaked session string or API hash the same as any other secret.

     Record the answer:
     - accepted → `"testSetupAccepted": "<runner>"`
     - they gave their own → put it straight in `commands.test` (`projects.<path>.test` for a
       sub-project)
     - "not now" → `"testSetupDeclined": "once"`
     - "never ask again" → `"testSetupDeclined": "always"`
     - no answer at all → record nothing. Silence is not a decline; the offer stands.

     **Never install anything at this point.** Adoption's job is to ask, and an install belongs
     in a branch, not in the step that reads the repository.
   - **Empty repository?** If every command is `null` and `projects` is empty — the
     `project-init` path, where the code does not exist yet — say so, record what you have, and
     set `"adoptedFrom": "empty"`. The first later step that finds a manifest re-runs ADOPT
     rather than reporting "not configured" for the rest of the project's life.
4. **STOP HERE** until the user has confirmed both halves. This is a user gate in everything but
   name: everything the lifecycle later runs against their code comes from these two answers.
5. Only then write `.bergant-workflow.json` at the project root — `commands` holds the root's
   commands, all `null` when the root is not a project — then regenerate
   `docs/bergant-workflow-commands.md` from it (see "Project commands" above), and commit both
   by exact path, never with `-A` or `.` (do not write or ask about `compactGate`: absent means off, the user
   adds it by hand to opt in, and re-running ADOPT keeps a value already there) — together with `CLAUDE.md` or `AGENTS.md` if the
   pointer line was just added to it, or the tree is left dirty right before the branch is cut:
   ```
   git add .bergant-workflow.json docs/bergant-workflow-commands.md [CLAUDE.md|AGENTS.md] && git commit -m "chore: adopt bergant-workflow"
   ```
   If the tree was dirty and the user chose to continue anyway, do **not** commit — write the
   file, say it is uncommitted, and let them commit it with their own work. Then continue with
   the rest of CONTEXT_CHECK.

## CONTEXT_CHECK

- Sets up the branch and the state file, and, only when the project opted in, enforces context
  cleanup before real work begins.
- **Compact gate: read `compactGate` from `.bergant-workflow.json`.** Only `true` turns it on.
  Missing field, missing file or any other value means **off**, the default: heavy steps run in
  sub-agents, so the main context stays small and a forced `/compact` only gets in the way.
- **Order on `start`, and it is not negotiable:** git preflight → ADOPT (if the project has not
  been adopted) → create the branch → write the state file with `awaitingCompact: true` when the
  gate is on, `awaitingCompact: false` when it is off.
  Setting the flag earlier blocks the agent that would have run ADOPT, so adoption lands after
  the compact instead of before the work — two runs of the same command then ask their questions
  in different orders. Adoption is a read plus one question; it belongs before the flag.
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
- **Refresh the project commands**, on the new branch: regenerate
  `docs/bergant-workflow-commands.md` (see "Project commands" at the top). If it changed, show
  the user the diff in one message — a new line is a check the steps will now run, a removed
  one a check they no longer will — and leave the file for the slice's commit. Two cases get a
  concrete proposal, applied only if they say yes:
  - a top-level command of the form `cd <sub-project> && …` (written before discovery
    existed): propose moving it to `projects.<sub-project>` without the `cd`. Until then it is
    already treated as that sub-project's command and runs once, not twice.
  - a check that is new for an existing project and that the user may not want (`ruff format
    --check` beside `ruff check`, say): propose a `projects.<path>` override that keeps the old
    behaviour.
- **Gate off:** do not print "Run /compact". In the same run, mark CONTEXT_CHECK completed and
  advance exactly as "On resume after compact" below says: SCOPE (present and STOP), or PLAN
  with `--skip-scope`.
- **Gate on** — everything below applies unchanged:
- **End the return message with a ready-to-paste compact prompt** (see "Compact prompt" below).
  Never just say "run /compact": the user should be able to copy one block and go.
- After `/compact`: SessionStart(compact) hook clears `awaitingCompact`.
- The gate blocks agent launches and edit tools while the flag is set; `Bash` is deliberately
  left alone so the user can still look around while deciding. If the user explicitly says to
  continue without compacting, run `/bergant-workflow:lifecycle skip-compact`: set
  `awaitingCompact: false`, `compactSkippedAt` to the current ISO timestamp, and
  `compactSkippedBefore` to the step. Never do this without being asked.
- On resume after compact: mark CONTEXT_CHECK completed, advance to SCOPE.
  - If SCOPE already `"completed"` (via `--skip-scope`): skip to PLAN and begin executing.
  - If SCOPE `"pending"`: advance to SCOPE (user gate — present requirements and STOP).

### Compact prompt

Whenever a run stops on the compact gate (after `start`, after PLAN), its return message ends
with exactly this block, filled in. `/compact` takes free-text instructions, so the block is
the command itself: the user pastes it and nothing else. With the gate off, the end of PLAN
adds the same block as a hint (see PLAN), and nothing is blocked.

````
Перед <next step> нужен compact. Вставь:

```
/compact Сохрани для lifecycle: задача <task>, ветка <branch> от <baseBranch>, следующий шаг <next step>. Решения: <decisions the user took in this session that are not yet in a repo file>. Не закоммичено: <uncommitted paths, or "ничего">. Открыто: <questions waiting on the user, promised follow-ups>. Ограничения: <standing instructions from the user that still hold>.
```

Продолжить без compact: `/bergant-workflow:lifecycle skip-compact`.
````

Rules:
- One line after `/compact`, no line breaks: the command takes everything up to Enter.
- Only what a fresh context cannot read back from the repo or `.lifecycle-state.json`. Name
  files instead of retyping them.
- Keep it under ~600 characters. Drop a section rather than pad it.
- Write it in the language the user wrote the `start` arguments in.

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
- **Gate on** (`"compactGate": true` in `.bergant-workflow.json`):
  - **Set `"awaitingCompact": true`**.
  - Display `✅ PLAN completed.` and end the return message with the compact prompt (see
    "Compact prompt" under CONTEXT_CHECK), with COMPONENTS (or IMPLEMENT) as the next step.
  - Do NOT start COMPONENTS.
- **Gate off** (the default, also when the field is missing): leave `awaitingCompact` false,
  display `✅ PLAN completed.`, add the compact prompt (see "Compact prompt" under CONTEXT_CHECK)
  as an optional hint, worded "Если контекст разросся, можно сжать:" instead of "нужен
  compact", and advance to COMPONENTS in the same run — which stops at its
  user gate, or auto-skips to IMPLEMENT for a task with no UI.

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
- When all done: `bash "SCRIPTS_DIR/project-commands.sh" run build`, then `… run lint` — every
  project, see "Project commands". A project without the command is a reported skip.
- If pass: mark IMPLEMENT completed, advance.
- If fail: fix, re-check.

## VERIFY (gate: user)

- `bash "SCRIPTS_DIR/project-commands.sh" run build`, then `… run lint`: every project's
  build and every linter. Report each skip as not configured rather than substituting
  something.
- Display test plan: task-specific manual checks (user-facing checklist, not developer checklist).
- **STOP HERE.** `When done: /bergant-workflow:lifecycle complete VERIFY`
- Do NOT proceed further.

## TEST

- Write unit tests for new business logic, in whatever the project already uses — infer the framework from existing tests, never introduce a new one inside a slice.
- Write E2E tests if UI changed and the project has an E2E setup.
- `bash "SCRIPTS_DIR/project-commands.sh" run test` — the tests of **every** project, every
  time, not only the one this slice touched (and `… run e2e` if the slice touched UI). A
  failure in a project the slice did not touch is still a failure: report it, do not wave it
  through.
- Mark TEST completed, advance.

**No test runner yet?** This is about the projects the plan reports with status `none` only —
a `skipped` or `planned` one, or one whose test the config set to `null` on purpose, is not
missing anything. For each, check `.bergant-workflow.json` (`projects.<path>` for a sub-project,
the top level for the root) before deciding there is nothing to run:
- a test command, detected or configured → it runs.
- `testSetupAccepted` set → this is the slice that sets it up, in that project's directory. Install the runner with the
  project's own package manager, add the minimal config it needs, write the tests for this
  slice, run them. Record the resulting command (`commands.test`, or `projects.<path>.test`)
  unless detection already finds it — and in that case remove a `null` left there at
  adoption, which would otherwise keep switching the new tests off. Do not pin a version from memory — let the package manager resolve it.
- `testSetupDeclined: "once"` → **ask again here, and only here**: this is the first slice that
  actually added logic, so the cost of having no tests is concrete rather than hypothetical.
  Show what this slice would have been covered by. If they decline a second time, write
  `"testSetupDeclined": "always"` and stop asking for good.
- `testSetupDeclined: "always"` → skip, record
  `skipReason: "test setup declined"`, and never raise it again.
- None of the above → adoption never ran properly; run ADOPT.

**Skip condition — writing tests only.** If the slice added no business logic and touched no
UI — docs, config, or a pure refactor already covered by existing tests — writing new tests is
waived: write the reason into `steps.TEST.skipReason`. **The suite still runs**, it is quick,
and a config change is exactly what breaks a project nobody touched. Never skip silently: the `Stop` hook refuses to end
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
- Apply fixes, commit, `project-commands.sh run build` and `run lint`, mark completed, advance.

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
- Run final: `bash "SCRIPTS_DIR/project-commands.sh" run build`, then `… run test`.
- Regenerate `docs/bergant-workflow-commands.md`: a project created during the slice belongs
  in it.
- Commit remaining changes (if any), by exact path.
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
6. **Hand off to a fresh session.** The slice is merged, so this session's context is spent
   weight: suggest the user run `/clear`, then give them a ready-to-paste prompt for the next
   session. End the return message with exactly this block:

   ````
   Слайс закрыт. Чтобы начать следующий с чистым контекстом, выполни `/clear` и вставь:

   ```
   /bergant-workflow:lifecycle start <next-slice>

   Контекст:
   - <slice> влит в <baseBranch> (<short sha>, PR #<n>).
   - <what the next slice needs to know that is NOT in the repo docs: decisions taken
     during this slice, deviations from the plan, quirks found in real data, test data
     worth reusing and where it lives>
   - <debt and deferred manual checks opened by this slice, with file paths>
   - <constraints the user stated at `start` that still hold: deadlines, how to treat
     gates, what not to touch>
   ```
   ````

   Rules for the prompt:
   - `<next-slice>` is what `next` would pick: the lowest-numbered plan file whose `Status:`
     is not done. With `planGlob: null`, or no slice left, write
     `/bergant-workflow:lifecycle next` and say there is no planned slice left.
   - Carry forward only what a fresh session cannot read from the repo. Link files
     (`docs/tech-debt.md`, `docs/acceptance/<slice>.md`) instead of retyping them.
   - Re-state the user's standing instructions from this slice's `start` arguments if they
     still apply. Drop the ones that were about this slice only.
   - Write it in the language the user wrote the `start` arguments in.
   - If the user asked to be reminded of something when the slice closes, put the reminder
     above the block, not inside the prompt.
