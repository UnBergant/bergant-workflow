# `.bergant-workflow.json`

Written once by `ADOPT`, committed with the project. It describes the repository, not a run:
the state file is per-task and disappears at `CLOSE`, this one stays.

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

| Field | Meaning |
|-------|---------|
| `commands.build` / `.lint` / `.test` / `.e2e` | Exactly what to run. `null` means the project has none — the step reports the skip instead of substituting a guess |
| `planGlob` | Where task descriptions live. `null` means the project has no plan documents and scope comes from what the user says at `start` |
| `adoptedAt` | When the answers were confirmed |

Rules:

- **Never write it without asking.** Detection proposes, the user confirms. A wrong `test`
  command turns the TEST step into a step that always passes.
- **Never fall back to npm.** If `commands.test` is `null`, the project has no test command;
  running `npm run test` on a Go repository produces a confusing failure and nothing else.
- Editing it by hand is expected. Re-running `adopt` overwrites it after the same confirmation.
