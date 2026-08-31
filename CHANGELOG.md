# Changelog

All notable changes to this plugin are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/).

## [0.12.3] — 2026-08-31

### Fixed
- `project-init` declared `Glob` and `Grep` in `allowed-tools`. Neither exists as a tool in
  Claude Code 2.1.251, and the skill never named them — a declaration that could only ever be
  wrong. Removed.

### Note
- Both spellings of the sub-agent tool stay declared: a session exposes it as `Task`, a tool
  call reports as `Agent`, and which one a given build offers is not something a plugin should
  bet on.
- Each skill now says in a comment what its `allowed-tools` covers and why — the inline paths
  only, since every other command runs in a spawned agent with its own tools. Whether the field
  is enforced for skills today is not something this plugin should depend on either way.

## [0.12.2] — 2026-08-31

### Fixed
- **A README command that could not be run.** "Using it on an existing project" showed
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-project.sh"`. That variable is set for hooks by the
  harness — it is empty in a user's shell and in a `Bash` call inside a session — so anyone
  copying the line got `No such file or directory`. Replaced with a clone-and-run pair that was
  executed verbatim to check it.
- The claim that `/plugin` "does the same" as the two update commands was loose. `/plugin` opens
  the plugin manager; the deterministic path is the two CLI commands.

### Added
- **What the plugin costs in context, and how to check it yourself** rather than trust a number:
  `claude plugin details bergant-workflow` reports ~278 tokens added to every session at this
  version — the two skill descriptions. The hooks cost nothing in context; they run in the
  harness. A skill's instructions load only when it fires.

## [0.12.1] — 2026-08-31

### Fixed
- **`start` set the compact flag before adoption could run.** Two live runs of the same command
  ordered themselves differently: one adopted first and asked its questions immediately, the
  other wrote `awaitingCompact: true` first — which blocks the very agent ADOPT needs — and
  deferred adoption until after the compact. Both readings fitted the instructions, which is
  the defect. The order is now stated as a sequence in both the skill and the step: preflight,
  adoption, branch, then the flag.

## [0.12.0] — 2026-08-31

### Added
- **The test offer names every layer the project needs, not just the first one.** Detection
  already reported an e2e runner for UI projects and the offer dropped it, so a front end got
  offered unit tests and nothing that drives a browser — which is where a front end actually
  breaks. The e2e runner is now offered as its own yes or no.
- **What the project *is* changes what testing it means.** A Telegram bot's handlers are
  unit-testable; its conversation is not. Detection recognises a bot from its dependencies
  (`aiogram`, `python-telegram-bot`, `pyrogram`, `telethon`, `telegraf`, `grammy`,
  `node-telegram-bot-api`, `gramjs`) and reports `domain` plus an integration path — `telethon`
  for Python, `gramjs` for Node. It is offered as a third, optional layer, with its price said
  out loud: a second account, API credentials, real servers, slower, not for CI by default.
- The offer explains what the tool *is* — a client library that signs in as an ordinary user and
  messages the bot like a person would. The people who most need this offer are the ones who
  have never heard of the library, and "set up Telethon?" is not a question they can answer.
- Python detection reads `requirements.txt`, not only `pyproject.toml`.

### Fixed
- **The version tests were not hermetic.** They fetched the real published manifest, so the
  live release overrode the fixture: they passed only while the actual version happened to
  agree with them, and broke the moment it did not. `curl` is stubbed out of every case that is
  not deliberately testing the network — which also removes the live requests the suite made on
  every run.

106 test cases.

## [0.11.0] — 2026-08-31

### Added
- **A project with no tests gets an offer, not a shrug.** Removing the hardcoded Vitest and
  Playwright in 0.8.0 made the plugin stack-agnostic and quietly dropped one of its reasons to
  exist: most repositories have no tests, and not having to work out how to start is much of
  the value. Adoption now names a runner that fits the stack — Vitest, pytest, `go test`,
  `cargo test` — explains what it costs and what it buys, and **recommends yes**. Nothing is
  installed at adoption: the setup lands in the first slice that needs it, in that branch,
  through the same review as the code.
- "Not now" is not "never". A decline is recorded as `once` and the offer returns a single
  time, at the first slice that actually adds logic — where the cost of having no tests is
  concrete. A second decline is remembered for good. Silence records nothing at all, because a
  reflexive no and an unanswered question are not the same answer.
- `detect-project.sh` reports `testSetup` (runner, e2e runner, install command) and `hasUI`. No
  versions are named: pinning is left to the project's own package manager.

### Fixed — the tests were not testing enough
A mutation pass broke the code in 44 ways and found that 21 of them shipped green. The gaps
that mattered:
- **`inject-lifecycle-state.sh` had no behavioural test at all.** Deleting its `awaitingCompact`
  clear bricks the plugin — the compact gate then blocks every edit forever — and the suite
  stayed green. It now has five: state is restored, the flag is cleared, a value cannot forge a
  section header, free text stays fenced, and the fence cannot be closed by its own content.
- **Version comparison was untested on the one pair that matters.** The only fixture was
  `0.0.1` vs `9.9.9`, which sorts the same lexically and by version. `0.9.0 → 0.10.0` — the pair
  this project just crossed — is now covered, along with no-downgrade and silent-when-current.
- The throttle was tested for firing and never for expiring, so a throttle that never released
  would have shipped. The published manifest, the authoritative source, was never consulted by
  any test; it now is, through a stubbed `curl` rather than the network.
- The compact gate's update notice is documented twice and was structurally unreachable from
  the suite, because every compact-gate case disabled the check.
- **`bash tests/hooks.test.sh` versus `/bin/bash tests/hooks.test.sh` made no difference**: the
  hooks were launched with a bare `bash` from `PATH`, so the interpreter never reached the code
  under test and the README's bash-3.2 advice bought nothing. Hooks now run under the same
  interpreter as the suite.
- The suite was not hermetic: a stray `.lifecycle-state.json` above `$TMPDIR` flipped two cases.
- Deleting tests was invisible — 40% of the file could be removed and the run stayed green. The
  assertion count is now asserted.
- Detection was tested only on its happy path: lint commands, yarn/bun/npm, Rust, `Makefile`
  gap-filling, and the requirements-only entry phase had no coverage.
- The hook wiring check was a whitelist, so a fifth hook could be added without failing. It is
  an equality check now.
- CI's line-ending check skipped `scripts/`, the one directory it did not cover, and CI now
  prints its `bash --version` so the 3.2 claim can be checked rather than assumed.

100 test cases, up from 66.

## [0.10.0] — 2026-08-31

Findings from a five-lens review of the repository before it was shared publicly. Everything
below was reproduced before it was fixed.

### Fixed — enforcement
- **A step missing from `.steps` passed every gate.** A key that was absent read as neither
  completed nor pending, so a state file listing only the step it had just done cleared the Stop
  hook entirely. Which steps exist, and which of them are user gates, is now fixed in the hook
  rather than read from the file the model writes; a missing step counts as pending. Editing
  the state file can now only make the gates stricter.
- **`skip-compact` could not be reached through the gate it lifts.** It routed through an agent
  launch, and agent launches are exactly what the compact gate blocks — as was writing state,
  since `Write` is matched too. It now runs inline and writes state through `jq`, the one tool
  the gate does not match. The escape hatch the README promised did not exist until now.
- **A step left `in_progress` was invisible to the Stop hook.** Marking a step in progress and
  then moving on — the realistic way a step disappears — passed. Only the step named by
  `currentStep` is exempt now, which is what `--skip-scope` needs and nothing more.

### Fixed — untrusted input
- **State file contents reached privileged context raw.** Values were printed unescaped, so a
  newline in `currentStep` or an approved-scope entry could forge section headers, fake a
  completed user gate, or close the fence around untrusted text and continue outside it. A
  `.lifecycle-state.json` committed to a repository someone clones was a delivery vector for
  this. Values are now stripped of control characters and truncated, and the fence carries a
  per-run nonce.
- The compact gate's block message carried `currentStep` into the model the same way. Same fix.
- Version strings from the marketplace clone and the published manifest are validated as digits
  and dots before being used or printed.

### Fixed — blast radius
- **The state-file search escaped into `$HOME`.** With no `.git` above it, the walk continued to
  `/`, so one stale file in the home directory blocked every edit in every non-git project
  beneath it. The walk now stops at `$HOME` as well as at a repository boundary.
- **The update-check stamp was a predictable path in a shared `/tmp`.** Anyone able to
  pre-create it as a symlink had the hook truncate the target on every session start. It lives
  under `~/.cache/bergant-workflow/` now, and a symlink there is refused.
- A failed `awaitingCompact` clear used to pass silently, leaving the gate blocking every edit
  for the rest of the session. It now says so in the injected context.

### Fixed — instructions a model could not follow
- **`${CLAUDE_PLUGIN_ROOT}` does not expand inside reference files.** Reference files are read
  as raw bytes, so ADOPT's first instruction ran as `bash "/scripts/detect-project.sh"` and the
  whole adoption step collapsed into guessing. The path is now resolved in `SKILL.md`, where
  interpolation works, and passed into the agent prompt.
- **ADOPT committed to the user's repository before the git preflight ran**, with no staging
  command given. It now runs after the preflight, stages one exact path, and does not commit at
  all if the tree was dirty.
- **CLOSE could never mark a slice done.** It searched for `Status: in progress`, which nothing
  writes — `project-init` writes `Status: ⏳ pending`. `next` therefore returned the same slice
  forever. That was the loop the whole plugin closes with.
- `next` looked for a `⏳` marker on tasks; the template puts checkboxes on tasks and `⏳` on the
  slice header. It reads the real markers now, and has a branch for a project with no plan.
- Branch naming was `<task-key-lowercase>` with no definition, so `lifecycle start "Add user
  login"` produced a branch name with spaces. The slug rule is now written down.
- `recover` was routed but specified nowhere, leaving the model to invent which steps were
  complete — and that invention is what the gates then enforce. It now has a section, and it
  reconstructs conservatively: every user gate comes back `pending`, because no artefact on disk
  proves an approval happened.
- `DOCUMENT` told the model to update `MEMORY.md` and `design-issues.md`, which the plugin never
  creates. It now updates what exists and creates nothing.
- `COMPONENTS` mandated shadcn/ui, `.stories.tsx` and a Storybook build while rule 8 forbids
  assuming a toolchain. The workbench substep is now conditional on `commands.storybook`.
- `planGlob` was honoured in one rule and ignored in five other places that hardcoded
  `docs/plan/slice-*.md`.
- `adopt` was a documented command with no routing rule; `$CWD` in `project-init`'s agent prompt
  is not a variable that expands; both skills' `allowed-tools` named `Agent` but not `Task`.

### Fixed — detection
- Plan candidates were joined with `|`, so a filename containing a pipe or a newline was handed
  back as paths that do not exist. The list is JSON end to end now.
- `suggestedEntryPhase` could never reach `DECOMPOSITION`: it never looked for planning output.
  A project with `docs/plan/phase-*.md` was told to redo PLANNING.
- A project adopted while empty records `adoptedFrom: "empty"`, so a repository that gains a
  manifest later is re-adopted instead of reporting "not configured" for good.

### Fixed — documentation
- The README claimed `VERIFY` and `TEST` run npm, Vitest and Playwright, that the two skills are
  meant to be used together, and that the hooks enforce more than they do. It listed neither
  `project-init`'s gate-clearing command nor the fact that the plugin writes to the user's
  `CLAUDE.md` and `.gitignore`. A blank line split the hooks table so its last row rendered as
  literal text.

## [0.9.0] — 2026-08-31

### Added
- **`project-init start` works out where to enter and recommends it.** `--from <phase>` already
  existed, but it only did anything if the user passed it and knew the phase names — so on a
  repository that already had requirements, a PRD or an architecture document, the default was
  to walk the whole sequence and write documents that argue with the ones already there. `start`
  now reads the project first and says what it found: which artifacts exist, whether there is
  source code, and which phase to enter at. It recommends and the user confirms — a phase is
  never skipped silently, because a plan resting on a PRD nobody wrote is worse than a slow one.
- When a repository has code but no documents, `project-init` says plainly that for a single
  task it is the wrong tool and points at `lifecycle start`, which adopts the project and needs
  no plan document.
- `detect-project.sh` reports `docs` (requirements, prd, architecture, designSystem),
  `hasSourceCode` and `suggestedEntryPhase`.

### Changed
- README gained a **Which skill do I run?** table. Two skills shipped with nothing saying how
  they relate, and the obvious reading — that every project goes through both — is wrong for
  most existing repositories. Both skills now also open by saying when they apply.

## [0.8.0] — 2026-08-31

### Added
- **Adoption for existing projects.** The plugin assumed its own conventions: task context came
  from `docs/plan/slice-*.md` and every check ran `npm run …`. On a repository that already
  exists — which is most of them — the plan was somewhere else and the commands were wrong.
  The first `lifecycle start` in a project now runs `ADOPT`, which reads the repository with
  `scripts/detect-project.sh`, proposes what it found, and writes `.bergant-workflow.json` once
  the user has confirmed it.
- `scripts/detect-project.sh` — deterministic discovery, not prose. Reports stack and package
  manager (npm/pnpm/yarn/bun lockfiles, `go.mod`, `pyproject.toml`, `Cargo.toml`, `Makefile`),
  the build/lint/test/e2e commands that actually exist, and candidate plan documents. It only
  reports a command whose script it can see, never a guess, and `Makefile` targets fill gaps
  the primary stack could not name. Exits 0 on anything, including an empty directory.
- `.bergant-workflow.json`, documented in `references/project-config.md`: the confirmed
  commands and `planGlob`. Committed with the project, unlike the per-task state file. A `null`
  command means the project has none — the step reports the skip instead of substituting
  `npm run` on a repository that never asked for it.
- `lifecycle adopt` re-runs the discovery when a project changes.

### Changed
- `planGlob` replaces the hardcoded `docs/plan/slice-*.md`, and `null` is a valid answer: a
  project with no plan documents takes its scope from what the user says at `start`, with SCOPE
  as the gate that pins it down.
- TEST no longer names Vitest and Playwright as the frameworks. It infers what the project
  already uses and does not introduce a new one inside a slice.

## [0.7.0] — 2026-08-31

The two audit findings deferred from 0.6.0.

### Fixed
- **The compact gate now covers the edit tools, not just agent launches** (audit P1-1). The
  bypass was reproduced live: with `awaitingCompact: true`, a `Write` call created a file and
  the hook never ran. The matcher is now
  `Agent|Task|Edit|MultiEdit|Write|NotebookEdit`. `Bash` is deliberately excluded — reading
  logs, running tests and checking `git status` while deciding whether to compact is not what
  is being gated, and blocking all of it would trade a working session for context hygiene.
  The gate protects the *main* session's context; subagents have their own, which is why
  agent launches and direct edits are the two things worth stopping.

### Added
- `/bergant-workflow:lifecycle skip-compact` — the deliberate way through. It clears the flag
  and records `compactSkippedAt` and `compactSkippedBefore`, so a skip is a decision in the
  record rather than a hole. The skill is instructed never to run it unasked; the block message
  offers it to the user, not to itself.
- **Sourcing contract for `project-init`** (audit P2-5). Legal and compliance findings must
  name the jurisdiction, cite a primary source with a URL, and carry the date they were
  checked; unsourced ones are written as `UNVERIFIED — needs checking` rather than stated
  plainly, and the whole section is marked as needing a lawyer's sign-off. Version tables in
  the architecture and design-system documents gained "verified against" and "checked" columns:
  a pinned version comes from the registry or a release page on a given day, or it says
  `unpinned`. "Latest" is not a version.

## [0.6.0] — 2026-08-31

Remediation of an external audit of `v0.2.0` by the author of a Codex port. Their findings are
kept in the wording of the fixes below; where this release deliberately diverges from their
recommendation, it says so.

### Fixed
- **Git no longer assumes `master` and no longer touches work it does not own.** `CONTEXT_CHECK`
  discovers the real default branch from `origin/HEAD` (this repository has only `main`, so the
  hardcoded `git checkout master` could not run on the plugin's own source), refuses to start on
  a dirty tree, a detached HEAD, or an in-progress rebase/merge/cherry-pick, and pulls with
  `--ff-only`. `REVIEW` stages by explicit path — `git add -A`, `git add .` and `commit -a` are
  forbidden, so unrelated changes cannot ride along. `CLOSE` deletes branches with `-d` only.
  Diverging from the audit: on a dirty tree the run stops and asks. It never stashes, because
  hiding someone's uncommitted work is the same class of silent mutation the audit objects to.
- **Hooks find the state file by walking up to the repository root.** They used to read a bare
  relative path, so starting a session in a subdirectory made an active lifecycle look absent —
  and an absent lifecycle means every hook allows everything. The search stops at a `.git`
  boundary so a nested repository never picks up its parent's state.
- **A missing `jq` is now audible.** Without it the hooks read empty values and block nothing.
  That happened silently, which is the worst version: the skills still look enforced. When a
  lifecycle is active and `jq` is absent, the session now opens with a warning. It still does
  not block — a missing dependency should not brick the workflow, contrary to the audit's
  fail-closed recommendation.
- **Compact restoration no longer dumps the raw state file into context.** It emits the
  machine-readable fields explicitly, then passes free text (task title, approved scope,
  findings) through fenced, truncated and labelled as data. Those fields are model-written, so
  a `cat` of the whole file let whatever landed in them read as instructions.

### Changed
- The step-progress rule named the wrong tools. `TaskList`/`TaskUpdate` are Claude Code's
  multi-agent task family, gated behind `hasTaskListTools` and carrying owners and claims; the
  per-session checklist is `TodoWrite`. Neither is exposed to sessions in 2.1.251, so the rule
  could never execute. It is now an explicitly optional mirror of the state file: use a
  checklist tool if the session has one, skip silently otherwise. The state file stays the
  record, and `lifecycle status` renders it either way.

### Added
- README states plainly that the plugin targets React/Node, and recommends forking it for other
  stacks — the enforcement layer has nothing React-specific in it, only the toolchain does.
- README has a "What the hooks do not enforce" section: the state file is model-written, so the
  hooks enforce the order of the record rather than the truth behind it; the compact gate only
  sees agent launches; below the hook layer everything is prose.
- 29 test cases, including nested-directory resolution, the repository boundary, and the
  missing-`jq` warning.

## [0.5.1] — 2026-08-31

### Fixed
- The session-start notice is now shown by the CLI itself. Printing plain text put the line in
  Claude's context and nothing more, so whether the user ever saw it came down to the model
  deciding to mention it — advice, not a mechanism, which is the thing this plugin exists to
  avoid. Verified against a real session: with plain stdout the line reached the model but
  surfaced only when asked about directly. The hook now returns the JSON contract, with
  `systemMessage` for the user and `hookSpecificOutput.additionalContext` for Claude.
- `check-plugin-update.sh --text` keeps the old plain line for the compact gate, which appends
  it to its own stderr block.

## [0.5.0] — 2026-08-31

### Changed
- The update notice now runs on `SessionStart(startup|resume)` as well, and that is where it
  normally lands. Hanging it off the compact gate alone was wrong: that gate fires on
  `PreToolUse(Agent)`, and the first agent of a run launches before `.lifecycle-state.json`
  exists, so the hook allows it. Everything up to `PLAN` then happens inside that one agent —
  no further tool call, no further hook, no notice. A session that never reaches `IMPLEMENT`
  never saw it. `SessionStart` puts the line in context at the top of the session instead,
  with no lifecycle involved; the compact gate keeps appending it for sessions already running.
- The notice says explicitly that Claude must not run the update itself. A plugin update is new
  code on the user's machine — it is installed deliberately, not on a model's say-so.

## [0.4.1] — 2026-08-31

### Fixed
- `.gitattributes` pins `*.sh` to LF. The marketplace source is a git clone, so a Windows user
  with Git's default `core.autocrlf=true` got CRLF hook scripts, and bash aborts on those with
  `$'\r': command not found` followed by a syntax error — exiting **2**, which for these hooks
  means *block*. The result was not a plugin without enforcement but a plugin that could not be
  used: the `Stop` hook refused to end any turn (its `stop_hook_active` guard never got to run)
  and the compact gate refused every agent launch, both citing a bash syntax error. Present
  since 0.1.0. Existing clones pick the fix up on a fresh `claude plugin marketplace update`.

### Added
- README lists `bash` as a required dependency and states plainly that Windows is untested.

## [0.4.0] — 2026-08-31

### Added
- Update notice. Nothing told an install that it was stale: plugins do not self-update and the
  cache is keyed by version, so an install made in August stayed on that version indefinitely.
  The compact gate that opens every lifecycle now carries a one-line notice when a newer
  version is published, with the two commands that apply it.
- README has an `## Update` section. It only documented installing.

### Note
- `check-plugin-update.sh` is a helper, not a hook — `hooks.json` still wires three.
- The check runs at most once a day (stamp in `$TMPDIR`), times out after 3s, and is silent on
  any failure: no `jq`, no `curl`, no network, unreadable manifest, or already current. It
  reads the marketplace clone on disk first and the published manifest on `main` second.
- Nothing about your code or usage leaves the machine — it is a plain fetch of this project's
  `plugin.json`. Set `BERGANT_WORKFLOW_NO_UPDATE_CHECK=1` to disable it entirely.

## [0.3.0] — 2026-08-31

### Fixed
- `check-lifecycle-gate.sh` (`Stop`) now enforces the order of **all ten** steps, not just the
  five user gates. Previously an auto step could be dropped without anything noticing: `TEST`
  sits between two user gates, so a run could go `VERIFY` → `REVIEW` and ship a slice with no
  tests while every gate was still honoured. Skipping an auto step now blocks the turn with
  `LIFECYCLE ORDER VIOLATION`. The `LIFECYCLE GATE VIOLATION` message and behaviour for user
  gates are unchanged.
- An auto step counts as skipped only while `pending` — never started. `start --skip-scope`
  legitimately stops with `CONTEXT_CHECK` in progress and `SCOPE` already completed, and that
  run must not be blocked.

### Added
- `TEST` has an explicit skip condition, mirroring `COMPONENTS`: a slice with no new business
  logic and no UI change auto-completes the step and records why in `steps.TEST.skipReason`.
  A waived test step is now visible in the state file instead of silent.

### Note
- The hook no-ops on a state file with no `steps` object, so a lifecycle started under 0.2.0
  will not be blocked mid-run by the upgrade.

## [0.2.0] — 2026-08-27

### Changed
- GitHub operations in `lifecycle` now go through the `gh` CLI first (`gh pr create`,
  `gh pr merge --squash --delete-branch`), with the GitHub MCP server as the fallback.
  Previously the skill mandated the MCP server and explicitly forbade `gh`, which stalled
  `CLOSE` whenever the MCP connection dropped.

### Added
- README — an ASCII diagram of both skills: the `project-init` phases with the artifact
  each one writes, the slice handoff into `lifecycle`, and which steps are user gates
  versus compact gates.
- README — an install path for users with no SSH key on GitHub. The `owner/repo`
  shorthand clones over SSH; the explicit HTTPS url and a local checkout both work as
  marketplace sources instead.

### Note
- Installs made while `0.1.0` was current may hold a stale cache, because the plugin
  cache is keyed by version and the `gh` CLI change shipped before this bump. Run
  `claude plugin marketplace update bergant-workflow` to refresh.

## [0.1.0] — 2026-08-21

First public release.

### Added
- `project-init` skill — turns a spec into structured docs:
  `INPUT_VALIDATION → PRD → ARCHITECTURE → PLANNING → DECOMPOSITION → FINALIZE`.
  DECOMPOSITION writes task slices to `docs/plan/`.
- `lifecycle` skill — drives one feature end-to-end:
  `CONTEXT_CHECK → SCOPE → PLAN → COMPONENTS → IMPLEMENT → VERIFY → TEST → REVIEW → DOCUMENT → CLOSE`.
- Three hooks enforcing the lifecycle contract: `check-compact-gate.sh`
  (`PreToolUse(Agent)`), `inject-lifecycle-state.sh` (`SessionStart(compact)`),
  `check-lifecycle-gate.sh` (`Stop`).
- Marketplace manifest — the repo installs directly as a plugin marketplace.
- MIT license.

### Fixed
- `check-lifecycle-gate.sh` omitted `COMPONENTS` from its ordered step list, so the
  `COMPONENTS` user gate was never enforced by the `Stop` hook.

### Notes
- Optional agents and skills (design agents, second-opinion and design-system skills,
  GitHub and Jira MCP, Storybook) are not bundled. Every step that uses one falls back
  to a documented in-house path instead of blocking.

[0.2.0]: https://github.com/UnBergant/bergant-workflow/releases/tag/v0.2.0
[0.1.0]: https://github.com/UnBergant/bergant-workflow/releases/tag/v0.1.0
