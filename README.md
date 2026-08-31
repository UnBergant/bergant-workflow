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

## Update

Plugins do not update themselves, and the cache is keyed by version — an install stays on
whatever version it was made with until you say so:

```
claude plugin marketplace update bergant-workflow   # refresh the marketplace listing
claude plugin update bergant-workflow               # install the new version
```

Both steps matter: the first only refreshes metadata, the second is what swaps the version.
Restart Claude Code afterwards. `/plugin` does the same from inside a session.

So that a stale install is noticeable at all, the compact gate that opens every lifecycle
carries a one-line notice when a newer version exists. It compares the version in your
`plugin.json` against two sources — the marketplace clone on disk, which is only as fresh as
your last `marketplace update`, and this project's `plugin.json` on `main`, which is served
through a CDN and can lag a release by a few minutes — then prints the two commands above. It
runs at most once a day, times out after three seconds, and goes quiet on any failure: no
network, no `jq`, no `curl`, nothing to report. Opt out with:

```
export BERGANT_WORKFLOW_NO_UPDATE_CHECK=1
```

## How the enforcement works

The `lifecycle` skill keeps its state in `.lifecycle-state.json` at the project root. Three
hooks (wired via `hooks/hooks.json`, paths resolved with `${CLAUDE_PLUGIN_ROOT}`) read and
write that file:

| Hook script | Event | Purpose |
|-------------|-------|---------|
| `check-compact-gate.sh` | `PreToolUse(Agent)` | Blocks agent launches while `awaitingCompact: true` — forces a `/compact` before the heavy steps |
| `inject-lifecycle-state.sh` | `SessionStart(compact)` | Clears the flag and re-injects lifecycle state after compaction |
| `check-lifecycle-gate.sh` | `Stop` | Refuses to let Claude finish its turn if it started a step while an earlier one is unfinished |

`check-plugin-update.sh` sits next to them but is not wired into `hooks.json` — it is a helper
the compact gate calls to print the update notice described under [Update](#update).

The `Stop` hook is the one that matters. It walks the ten steps in order, finds the first one
that is not `completed`, and blocks if anything after it has already started:

- the unfinished step is a **user gate** (`gate: "user"`) — `LIFECYCLE GATE VIOLATION`. The gate
  clears only when you run `/bergant-workflow:lifecycle complete <step>`, so Claude has to come
  back and ask.
- the unfinished step is an **auto step** (`PLAN`, `IMPLEMENT`, `TEST`, `DOCUMENT`) —
  `LIFECYCLE ORDER VIOLATION`. Nothing to approve here; the step simply has to be finished, or
  auto-completed with its reason recorded in the state file, before the next one runs.

That second case is why `TEST` cannot quietly disappear from a slice. It is not a user gate — you
are never asked to approve tests — but `REVIEW` cannot start until `TEST` is closed one way or the
other.

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

Two things live outside the repo, both from the update check: a throttle stamp in `$TMPDIR`
holding a unix timestamp, and one daily `GET` of this project's `plugin.json` from
`raw.githubusercontent.com`. Nothing about your code, project or usage is sent — it is a plain
file fetch. `BERGANT_WORKFLOW_NO_UPDATE_CHECK=1` stops both.

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
│   ├── check-plugin-update.sh
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
