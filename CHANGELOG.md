# Changelog

All notable changes to this plugin are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/).

## [0.3.0] — 2026-08-31

### Fixed
- `check-lifecycle-gate.sh` (`Stop`) now enforces the order of **all ten** steps, not just the
  five user gates. Previously an auto step could be dropped without anything noticing: `TEST`
  sits between two user gates, so a run could go `VERIFY` → `REVIEW` and ship a slice with no
  tests while every gate was still honoured. Skipping an auto step now blocks the turn with
  `LIFECYCLE ORDER VIOLATION`. The `LIFECYCLE GATE VIOLATION` message and behaviour for user
  gates are unchanged.

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
