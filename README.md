# bergant-workflow

A Claude Code plugin that makes a long feature survive a long session.

Skills tell Claude what the process is. Hooks make sure it actually follows it — Claude
cannot skip a step you haven't approved, and cannot lose the plan to a `/compact`.

<!-- Demo GIF — drop the recording at .github/assets/demo.gif, then uncomment:
<p align="center">
  <img src=".github/assets/demo.gif" alt="A lifecycle gate blocking Claude mid-feature" width="800">
</p>
-->

## The problem

Give Claude Code a multi-hour feature and two things go wrong. It drifts — writes code before
the scope is agreed, marks itself done before tests run. And it forgets — one `/compact` and
the plan you spent twenty minutes on is gone.

Prompting your way around this doesn't hold, because a prompt is advice. This plugin encodes
the process as state on disk plus three hooks that read it, so the rules survive both
compaction and Claude's own optimism.

## What's in the box

| Component | Type | What it does |
|-----------|------|--------------|
| `project-init` | skill | Turns a spec into structured docs: `INPUT_VALIDATION → PRD → ARCHITECTURE → PLANNING → DECOMPOSITION → FINALIZE`. DECOMPOSITION writes task slices to `docs/plan/` |
| `lifecycle` | skill | Drives one feature end-to-end: `CONTEXT_CHECK → SCOPE → PLAN → COMPONENTS → IMPLEMENT → VERIFY → TEST → REVIEW → DOCUMENT → CLOSE` |
| 3 hooks | hooks | Enforce the compact-gate and the user-gates of `lifecycle` |

The two are meant to be used together: `project-init` breaks a spec into slices,
then `lifecycle next` picks up the next unfinished slice and runs it through the full cycle.

## The flow

```
                       docs/spec.md
                             |
   +========================v=================================+
   |  project-init                        spec -> documents   |
   +==========================================================+
   |  INPUT_VALIDATION   [gate]  ->  docs/REQUIREMENTS.md     |
   |  PRD                [gate]  ->  docs/prd.md              |
   |  ARCHITECTURE       [gate]  ->  docs/architecture.md     |
   |  PLANNING           [gate]  ->  docs/plan/phase-N.md     |
   |  DECOMPOSITION      [gate]  ->  docs/plan/slice-NNN.md   |
   |  FINALIZE           [auto]  ->  CLAUDE.md + .gitignore   |
   +==========================================================+
                             |
                slice-001, slice-002, slice-003 ...
                             |
                             v
              /bergant-workflow:lifecycle next
                             |
   +========================v=================================+
   |  lifecycle                        one slice at a time    |
   +==========================================================+
   |  CONTEXT_CHECK     [cmpct]  branch + forced /compact     |
   |  SCOPE             [gate]   scope read + second opinion  |
   |  PLAN              [cmpct]  explore + component inventory|
   |  COMPONENTS        [gate]   tokens, components, stories  |
   |  IMPLEMENT                  subtasks by agents, build    |
   |  VERIFY            [gate]   build, lint, manual test plan|
   |  TEST                       Vitest unit + Playwright e2e |
   |  REVIEW            [gate]   secret scan, commit, review  |
   |  DOCUMENT                   MEMORY.md / CLAUDE.md update |
   |  CLOSE             [gate]   PR create -> merge -> clean  |
   +==========================================================+
                             |
                             +-----> next slice (repeat)

   [gate]   user gate    - Stop hook blocks until `complete <step>`
   [cmpct]  compact gate - PreToolUse(Agent) hook blocks until `/compact`
```

## Install

This repo doubles as a plugin marketplace, so it installs straight from git:

```
/plugin marketplace add UnBergant/bergant-workflow
/plugin install bergant-workflow@bergant-workflow
```

Then, in a project:

```
/bergant-workflow:project-init start docs/spec.md     # spec → PRD → architecture → slices
/bergant-workflow:lifecycle next                      # pick up the next slice
/bergant-workflow:lifecycle status                    # where am I?
```

Commands are namespaced under `bergant-workflow:` after install.

### No SSH key on GitHub?

The `owner/repo` shorthand above is cloned over SSH. If you have no SSH key set up,
that step fails — pass the HTTPS URL explicitly instead and everything else is identical:

```
/plugin marketplace add https://github.com/UnBergant/bergant-workflow.git
/plugin install bergant-workflow@bergant-workflow
```

A local checkout works as a marketplace source too, if you would rather clone it yourself:

```
git clone https://github.com/UnBergant/bergant-workflow
/plugin marketplace add ./bergant-workflow
```

To try it without installing:

```
git clone https://github.com/UnBergant/bergant-workflow
claude --plugin-dir ./bergant-workflow
```

## How the enforcement works

The `lifecycle` skill keeps its state in `.lifecycle-state.json` at the project root. Three
hooks (wired via `hooks/hooks.json`, paths resolved with `${CLAUDE_PLUGIN_ROOT}`) read and
write that file:

| Hook script | Event | Purpose |
|-------------|-------|---------|
| `check-compact-gate.sh` | `PreToolUse(Agent)` | Blocks agent launches while `awaitingCompact: true` — forces a `/compact` before the heavy steps |
| `inject-lifecycle-state.sh` | `SessionStart(compact)` | Clears the flag and re-injects lifecycle state after compaction |
| `check-lifecycle-gate.sh` | `Stop` | Refuses to let Claude finish its turn if it moved past a step you never approved |

The `Stop` hook is the one that matters. A step marked `gate: "user"` only clears when you run
`/bergant-workflow:lifecycle complete <step>`. If a later step starts while that gate is still
open, the hook blocks with a `LIFECYCLE GATE VIOLATION` and Claude has to come back and ask.

## What it writes to your repo

Worth knowing before you install something that ships hooks:

- `.lifecycle-state.json` — project root, git-ignored, deleted automatically on `CLOSE`.
  It lives at the root rather than under `.claude/` because the latter triggers a
  write-permission prompt on every single update.
- `docs/spec-state.json` — `project-init` phase tracking, git-ignored.
- `docs/` — the generated PRD, architecture and `docs/plan/slice-*.md` files. These are
  yours to commit.

The hooks only ever touch `.lifecycle-state.json`, and they no-op entirely when that file
does not exist — so with no active lifecycle, the plugin is inert.

## Requirements

**Required**

- `jq` — all three hook scripts use it to read and update the state file (`brew install jq`).
  Without it the hooks silently no-op, which means gate enforcement is off and you get the
  skills without the guarantees.

**Optional** — every one of these degrades gracefully. The first time a step needs a missing
tool, the skill offers a one-time choice: set it up now, or skip that step and note the skip.
Nothing here hard-blocks the workflow.

| Dependency | Used by | If absent |
|------------|---------|-----------|
| `gh` CLI (authenticated) | `lifecycle` REVIEW / CLOSE (PR create & merge) | falls back to the GitHub MCP server; without either, you open the PR yourself |
| Storybook | `lifecycle` COMPONENTS | the component-review substep is skipped |
| A second-opinion skill driving an external model | SCOPE and REVIEW cross-checks | in-house review agent only |
| Design agents (`brand-agent`/`ux-agent`/`visual-agent`/`ui-agent`) | `project-init` design-system step | a `general-purpose` agent produces the same `BRIEF.md` with less specialization |
| `interface-design`, Vercel and `frontend-design` skills | `project-init` design-system step | the same checks are applied inline and the docs record that |
| Jira MCP (`mcp__atlassian__*`) | `project-init` DECOMPOSITION → optional sync | Jira sync skipped, slices stay in `docs/plan/` |

None of the optional agents or skills are bundled here — this plugin stays small on purpose,
and the skills are written to work without them.

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
├── CHANGELOG.md
└── README.md
```

## Uninstall

```
/plugin uninstall bergant-workflow@bergant-workflow
/plugin marketplace remove bergant-workflow
```

Delete any leftover `.lifecycle-state.json` if a lifecycle was interrupted before `CLOSE`.

## License

MIT — see [LICENSE](LICENSE).
