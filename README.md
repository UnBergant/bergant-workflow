# bergant-workflow

[![linux](https://github.com/UnBergant/bergant-workflow/actions/workflows/tests-linux.yml/badge.svg)](https://github.com/UnBergant/bergant-workflow/actions/workflows/tests-linux.yml) [![macos](https://github.com/UnBergant/bergant-workflow/actions/workflows/tests-macos.yml/badge.svg)](https://github.com/UnBergant/bergant-workflow/actions/workflows/tests-macos.yml) [![windows](https://github.com/UnBergant/bergant-workflow/actions/workflows/tests-windows.yml/badge.svg)](https://github.com/UnBergant/bergant-workflow/actions/workflows/tests-windows.yml)

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

## What this assumes about your project

It is built for **React/Node**, and it does not pretend otherwise. `VERIFY` and `TEST` run
`npm run build`, `npm run lint`, Vitest and Playwright; `project-init` defaults to an
FSD-lite layout with Biome, Tailwind, shadcn and Radix. On a Python, Go, PHP or Rust
repository those commands are simply wrong.

That is deliberate rather than unfinished. The point of the plugin is to remove decisions from
every task — a stack it has to discover each time is a decision it did not remove. If your
stack is different, **fork it and change the commands**: the enforcement layer (the hooks, the
state file, the ten steps, the gates) has nothing React-specific in it, and the toolchain lives
in `skills/lifecycle/references/steps.md` and `skills/project-init/references/phases.md`.

If your fork touches the hooks, run `bash tests/hooks.test.sh` (the suite behind the badges —
`bash`, `jq` and Python, about a second). A broken hook does not fail loudly: without `jq` it
allows everything, and with CRLF line endings it blocks everything. On macOS run it once with
`/bin/bash`, which is 3.2 — that is what CI uses, and it parses differently from Homebrew's.

## Using it on an existing project

Most projects that install this already exist, so the first `lifecycle start` in a repository
runs an adoption step before anything else. It reads the project rather than assuming it:

```
bash scripts/detect-project.sh
```

That reports the stack and package manager, the real `build` / `lint` / `test` / `e2e`
commands — taken from `package.json` scripts, `Makefile` targets, `go.mod`, `pyproject.toml` —
and any file that looks like an existing plan. Then it asks you to confirm both halves once,
and writes `.bergant-workflow.json`, which is committed with the project.

Two things it will not do. It will not invent a command: a repository with no lint script has
no lint step, and `VERIFY` says it skipped rather than running something that was never set up.
And it will not decide what your plan is — if there is one obvious candidate it proposes it, if
there are several it lists them, and "there is no plan, take the scope from what I tell you" is
a normal answer. Slices are how it prefers to work, not a precondition.

Safety on an established repository comes from the git preflight: a dirty tree stops the run
and asks, the base branch is discovered rather than assumed, staging is by explicit path, and
branch deletion is `-d` only. It will not move, hide or sweep up work it did not create.

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
   [cmpct]  compact gate - PreToolUse hook blocks agents and edits until `/compact`
            (or an explicit `lifecycle skip-compact`)
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

### Commands

| Command | What it does |
|---------|--------------|
| `project-init start <spec>` | Spec → requirements → PRD → architecture → plan → slices |
| `lifecycle start <task>` | Git preflight, then open a lifecycle for one slice. `--skip-scope` when the scope is already agreed |
| `lifecycle next` | Pick up the next unfinished slice |
| `lifecycle status` | Where am I — the step table, gates marked, `IMPLEMENT` subtasks |
| `lifecycle complete <step>` | Your approval on a user gate. The only thing that clears one |
| `lifecycle advance` | Move to the next step when the current one is done |
| `lifecycle skip-compact` | Continue without compacting, on purpose. Recorded in state |
| `lifecycle adopt` | Learn an existing project: detect its commands and plan, confirm, write `.bergant-workflow.json`. Runs automatically on the first `start` |
| `lifecycle recover` | Rebuild state from git, build and tests when the state file is lost |

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

So that a stale install is noticeable at all, a notice appears at the top of a session when a
newer version exists — and again on the block that opens a lifecycle, for sessions that were
already running. The session-start one is shown to you by the CLI itself, not relayed by
Claude: the hook returns `systemMessage` alongside the context, so the line does not depend on
the model choosing to mention it. It compares the version in your
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
write that file. A fourth wiring carries no enforcement at all — it only reports a stale
install:

| Hook script | Event | Purpose |
|-------------|-------|---------|
| `check-compact-gate.sh` | `PreToolUse(Agent\|Task\|Edit\|Write\|…)` | Blocks agent launches and edits while `awaitingCompact: true` — forces a `/compact` before the heavy steps. `Bash` is not matched |
| `inject-lifecycle-state.sh` | `SessionStart(compact)` | Clears the flag and re-injects lifecycle state after compaction |
| `check-lifecycle-gate.sh` | `Stop` | Refuses to let Claude finish its turn if it started a step while an earlier one is unfinished |

| `check-plugin-update.sh` | `SessionStart(startup\|resume)` | Prints the update notice described under [Update](#update) — at most once a day, silent when current |

`check-plugin-update.sh` has two callers: the `SessionStart` wiring above, and the compact gate,
which appends the same line to the block that opens a lifecycle.

The `Stop` hook is the one that matters. It walks the ten steps in order, finds the first one
that is not `completed`, and blocks if anything after it has already started:

- the unfinished step is a **user gate** (`gate: "user"`) — `LIFECYCLE GATE VIOLATION`. The gate
  clears only when you run `/bergant-workflow:lifecycle complete <step>`, so Claude has to come
  back and ask.
- the unfinished step is an **auto step** (`PLAN`, `IMPLEMENT`, `TEST`, `DOCUMENT`) —
  `LIFECYCLE ORDER VIOLATION`. Nothing to approve here; the step simply has to be finished, or
  auto-completed with its reason recorded in the state file, before the next one runs.

The compact gate is the one gate meant to be waved through. Its job is to stop you sliding
into the next step on a bloated context without noticing — not to decide for you. When it
blocks, you either run `/compact` or run `/bergant-workflow:lifecycle skip-compact`, which
clears the flag and records that you chose to. The skill is told never to run that on its own.

That second case is why `TEST` cannot quietly disappear from a slice. It is not a user gate — you
are never asked to approve tests — but `REVIEW` cannot start until `TEST` is closed one way or the
other.

### What the hooks do not enforce

Worth being precise, because the whole pitch is that hooks beat prompts:

- **The state file is written by the model.** The hooks read it, so they enforce the *order of
  the record*, not the truth behind it. A gate marked `completed` is taken at its word. What
  the hooks make impossible is drifting past a gate by forgetting; what they cannot make
  impossible is a deliberate false entry.
- **The compact gate does not match `Bash`.** It covers agent launches and the edit tools, so
  the session cannot quietly start writing code before compacting, but a shell command can
  still change files. That is a deliberate trade: reading logs and running tests while you
  decide whether to compact is not what is being gated.
- **Everything is prose below the hook layer.** The steps themselves — what `TEST` writes, how
  `REVIEW` stages — are instructions to a model. The hooks bound the sequence, not the content.
- **Anything with write access can disable it.** Deleting `.lifecycle-state.json` ends
  enforcement, which is the intended escape hatch, not a hole to plug.

Branch protection, CI and human review remain the real boundary. This plugin makes a long task
survive a long session; it is not a security control.

## What it writes to your repo

Worth knowing before you install something that ships hooks:

- `.bergant-workflow.json` — project root, written once by adoption, **meant to be committed**.
  It records the build/lint/test commands you confirmed and where your plan lives.
- `.lifecycle-state.json` — project root, git-ignored, deleted automatically on `CLOSE`.
  It lives at the root rather than under `.claude/` because the latter triggers a
  write-permission prompt on every single update. The hooks find it by walking up from the
  session's directory to the repository root, so working in a subdirectory does not silently
  switch enforcement off.
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

- `bash` — every hook is a bash script, wired as `bash <script>` in `hooks.json`. macOS and
  Linux have it. On Windows it means Git Bash (ships with Git for Windows) or WSL, reachable
  as `bash` from whatever shell Claude Code launches hooks in.
- `jq` — all three hook scripts use it to read and update the state file (`brew install jq`).
  Without it the hooks silently no-op, which means gate enforcement is off and you get the
  skills without the guarantees.

A missing `jq` leaves the hooks unable to read state, and a hook that cannot read state does
not block. That used to happen in silence; now, whenever a lifecycle is active and `jq` is
absent, the session opens with a warning saying gates are not being enforced. If you want to
confirm it yourself, start a lifecycle and try to skip a gate — you should be stopped.

**Platform.** The hook suite runs on ubuntu, macos and windows on every push — on Windows
under Git Bash, which is what Claude Code would use there. What CI cannot cover is Claude Code
itself on Windows: whether it hands `${CLAUDE_PLUGIN_ROOT}` to `bash` in a form Git Bash
accepts. If you run this on Windows, a report either way is welcome.

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
| A session checklist tool (`TodoWrite`) | `lifecycle` progress rendering | step status still lives in the state file; `lifecycle status` prints the same table. Not every build exposes the tool |

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
├── scripts/
│   └── detect-project.sh
├── hooks/
│   ├── hooks.json
│   ├── lib-state.sh
│   ├── check-plugin-update.sh
│   ├── check-compact-gate.sh
│   ├── inject-lifecycle-state.sh
│   └── check-lifecycle-gate.sh
├── tests/
│   └── hooks.test.sh
├── .github/workflows/
│   ├── tests.yml            reusable body
│   ├── tests-linux.yml
│   ├── tests-macos.yml
│   └── tests-windows.yml
├── .gitattributes
├── CHANGELOG.md
├── LICENSE
└── README.md
```

## Uninstall

```
/plugin uninstall bergant-workflow@bergant-workflow
/plugin marketplace remove bergant-workflow
```

Delete any leftover `.lifecycle-state.json` if a lifecycle was interrupted before `CLOSE`.

## Author

Igor Druzhinin — [LinkedIn](https://www.linkedin.com/in/igor-druzhinin/)

## License

MIT — see [LICENSE](LICENSE).
