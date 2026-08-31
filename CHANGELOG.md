# Changelog

All notable changes to this plugin are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/).

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
