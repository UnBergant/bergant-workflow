# `.bergant-workflow.json`

Written once by `ADOPT`, committed with the project. It describes the repository, not a run:
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

| Field | Meaning |
|-------|---------|
| `commands.build` / `.lint` / `.test` / `.e2e` | Exactly what to run. `null` means the project has none — the step reports the skip instead of substituting a guess |
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
- Editing it by hand is expected. Re-running `adopt` overwrites it after the same confirmation.
