# bergant-workflow

A Claude Code **plugin** bundling two engineering-workflow skills plus the hooks that
enforce their gates:

| Component | Type | What it does |
|-----------|------|--------------|
| `project-init` | skill | Turns a spec/ТЗ into structured docs: `INPUT_VALIDATION → PRD → ARCHITECTURE → PLANNING → DECOMPOSITION → FINALIZE` (DECOMPOSITION writes task slices to `docs/plan/`; Jira optional) |
| `lifecycle` | skill | Orchestrates a feature end-to-end: `CONTEXT_CHECK → SCOPE → PLAN → COMPONENTS → IMPLEMENT → VERIFY → TEST → REVIEW → DOCUMENT → CLOSE` |
| 3 hooks | hooks | Enforce the compact-gate and user-gates of `lifecycle` (see below) |

After install the commands are **namespaced**:

```
/bergant-workflow:project-init …
/bergant-workflow:lifecycle …
```

## Install

This repo doubles as a plugin **marketplace**. No need to publish to the official
Anthropic marketplace — install straight from git:

```
/plugin marketplace add <owner>/bergant-workflow      # or the full git URL
/plugin install bergant-workflow@bergant-workflow
```

To test locally before pushing:

```
claude --plugin-dir ~/Projects/bergant-workflow
```

## Hooks

The `lifecycle` skill relies on three hooks (wired via `hooks/hooks.json`,
paths resolved with `${CLAUDE_PLUGIN_ROOT}`):

| Hook script | Event | Purpose |
|-------------|-------|---------|
| `check-compact-gate.sh` | `PreToolUse(Agent)` | Blocks agent launches while `awaitingCompact:true` — forces a `/compact` before heavy steps |
| `inject-lifecycle-state.sh` | `SessionStart(compact)` | Clears the flag and re-injects lifecycle state after compaction |
| `check-lifecycle-gate.sh` | `Stop` | Prevents finishing if a user gate was skipped |

**State file:** `lifecycle` keeps its state at the **project root** as `.lifecycle-state.json`
(not under `.claude/`, which would trigger a write-permission prompt on every update).
It is git-ignored and deleted automatically on the `CLOSE` step.

## Requirements

**Required**
- `jq` — used by all three hook scripts to read/update the state file
  (`brew install jq`).

**Recommended (soft dependencies)** — features degrade gracefully if missing; the skill
will offer to set them up once or skip the relevant step:

| Dependency | Used by | If absent |
|------------|---------|-----------|
| OpenAI Codex CLI (`toxic-opinion` skill) | second-opinion steps in both skills | step skipped, in-house review used |
| GitHub MCP server | `lifecycle` REVIEW/PR steps | PR automation skipped |
| Storybook | `lifecycle` COMPONENTS step | component-review step skipped |
| design-agents (`ui-agent`/`ux-agent`/`visual-agent`/`brand-agent`) | `lifecycle` COMPONENTS / design tasks | manual/no design pass |

> design-agents are plain markdown and are **not** bundled here by choice — keep this
> plugin minimal. Add them to your `~/.claude/agents/` separately if you want the
> design pipeline.

## Layout

```
bergant-workflow/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── skills/
│   ├── project-init/
│   └── lifecycle/
├── hooks/
│   ├── hooks.json
│   ├── check-compact-gate.sh
│   ├── inject-lifecycle-state.sh
│   └── check-lifecycle-gate.sh
└── README.md
```
