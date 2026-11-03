# `.bergant-workflow.json`

Written once by `ADOPT` (or started by `project-init` with the planned layout), committed with
the project. It describes the repository, not a run:
the state file is per-task and disappears at `CLOSE`, this one stays.

A minimal one, for a project that already had everything:

```json
{
  "commands": {
    "build": "npm run build",
    "lint": "npm run lint",
    "test": "npm run test",
    "e2e": null
  },
  "planGlob": "docs/plan/slice-*.md",
  "adoptedAt": "2026-08-31T14:00:00Z"
}
```

And one carrying every field this file can hold — a Telegram bot with no tests yet, whose owner
accepted the runner and the integration layer:

```json
{
  "commands": {
    "build": null,
    "lint": "ruff check .",
    "test": null,
    "e2e": null,
    "storybook": null
  },
  "planGlob": null,
  "testSetupAccepted": "pytest",
  "integrationTest": "telethon",
  "adoptedFrom": "empty",
  "adoptedAt": "2026-08-31T14:00:00Z"
}
```

`testSetupDeclined` appears instead of `testSetupAccepted` when the offer was turned down —
`"once"` after the first no, `"always"` after the second.

And a repository of several projects with no manifest at the root — a Swift package, a uv
project, a web app planned by `project-init` but not created yet, and a repository-wide check
that belongs to none of them:

```json
{
  "commands": {
    "build": null,
    "lint": null,
    "test": "scripts/validate-schemas.sh",
    "e2e": null
  },
  "projects": {
    "recorder": { "lint": "swift format lint --strict --recursive Sources Tests" },
    "transcribe": {},
    "web": { "stack": "node", "planned": true },
    "tools/legacy": { "skip": true }
  },
  "exclude": ["vendor-forks"],
  "planGlob": "docs/plan/slice-*.md",
  "adoptedAt": "2026-08-31T14:00:00Z"
}
```

Here `recorder` and `transcribe` need no entry to be found — they are one level down and have
manifests — but listing them is harmless, and an entry is where their overrides go. Their
detected `swift build`, `swift test`, `uv run pytest` and `uv run ruff …` all run; only the
recorder's lint is set by hand, because swift-format is only detected when a `.swift-format`
configuration is committed.

**How a command is chosen, per project and per check** (`scripts/project-commands.sh`):

1. `projects.<path>.skip: true` → the project is left out.
2. `projects.<path>.<kind>` present → it wins; `null` means "this project has none".
3. The root (`.`) → `commands.<kind>` when the key is present, `null` included.
4. Otherwise → what detection found. A missing key always inherits; only `null` disables.

A top-level `commands.<kind>` that is not about the root is not lost: with no root project it
runs at the root beside the sub-projects, and written as `cd <sub-project> && …` it is treated
as that sub-project's command, so a configuration from before discovery runs each check once.

| Field | Meaning |
|-------|---------|
| `commands.build` / `.lint` / `.test` / `.e2e` | The root's commands, overriding what detection found there. `null` means the root has none — the step reports the skip instead of substituting a guess. Sub-projects are checked as well; see `projects` |
| `projects` | Optional. Keyed by path relative to the root. Each entry may override `build` / `lint` / `test` / `e2e` (string replaces, `null` disables), set `"skip": true`, or record `testSetupAccepted` / `testSetupDeclined` for that project. A listed path is always checked, however deep; one whose code does not exist yet is reported as planned until its manifest appears. `stack` and `planned` are written by `project-init` |
| `exclude` | Optional. Paths the sub-project scan ignores, with everything under them. Gitignored directories, dependency trees, build output, `fixtures`, `testdata` and `templates` are ignored already |
| `commands.storybook` | Optional. The component workbench build, if the project has one. Absent means COMPONENTS skips that substep rather than scaffolding a workbench |
| `integrationTest` | An accepted integration path for what this project *is* — e.g. `telethon` for a Telegram bot, which drives it as a real user. Needs credentials and network, so it is never assumed and never run in CI by default |
| `testSetupAccepted` | The runner the user agreed to add, when the project had no tests. The first slice that needs tests installs it and fills in `commands.test` |
| `testSetupDeclined` | `"once"` — declined at adoption; the offer returns once, at the first slice that adds real logic. `"always"` — declined twice, never raised again. Absent means it has not been asked yet, and silence never sets it |
| `adoptedFrom` | `"empty"` when the project had no manifest yet — the first step that finds one re-runs adoption instead of reporting "not configured" forever |
| `planGlob` | Where task descriptions live. `null` means the project has no plan documents and scope comes from what the user says at `start` |
| `adoptedAt` | When the answers were confirmed |

Rules:

- **Never write it without asking.** Detection proposes, the user confirms. A wrong `test`
  command turns the TEST step into a step that always passes.
- **Never fall back to npm.** If `commands.test` is `null`, the project has no test command;
  running `npm run test` on a Go repository produces a confusing failure and nothing else.
- Editing it by hand is expected. Re-running `adopt` overwrites it after the same confirmation,
  keeping `projects` and `exclude`.
- **It is not the list of commands.** Discovery is redone at every step; this file only says
  where the project differs from what discovery finds. The list people read is
  `docs/bergant-workflow-commands.md`, generated from both.
