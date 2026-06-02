# Phase Execution Details

Read only the phase you need — each is self-contained.

---

## INPUT_VALIDATION

**Goal:** Ensure the spec is workable before investing in analysis.

**Step 1 — Ambiguity Gate.** Scan the spec for:
- Vague requirements ("fast", "convenient", "user-friendly" without criteria)
- Contradictions between sections
- Missing constraints (limits, volumes, deadlines, target platforms)
- Undefined terms or acronyms
- Missing user/stakeholder definition

**Step 2 — Completeness Check.** Verify the spec addresses:
- Problem statement / business goal
- Target users
- Core functionality
- Non-functional requirements (performance, security, availability)
- Constraints (timeline, tech stack, integrations, budget)
- Success criteria

**Step 3 — Extract & structure** into `docs/REQUIREMENTS.md`:
```markdown
# Requirements

## Source
<spec reference>

## Problem Statement
<extracted or "NOT DEFINED — needs clarification">

## Target Users
<extracted or "NOT DEFINED">

## Functional Requirements
- FR-1: ...

## Non-Functional Requirements
- NFR-1: ...

## Constraints
- ...

## Open Questions
- Q1: <ambiguity or missing info>

## Assumptions
- A1: <assumption made due to missing info>
```

**Step 4 — Second opinion** (IMPORTANT — always ask):
- **You MUST ask the user:** "Want to run `/toxic-opinion` for a critical review of the extracted requirements?"
- Do NOT skip this question. Do NOT proceed to the gate without asking.
- If user agrees and `/toxic-opinion` skill is available → invoke it with: "Critically evaluate these requirements. Missing constraints? Unrealistic assumptions? Contradictions? What will block development?"
- Synthesize findings into `docs/REQUIREMENTS.md`
- If user declines → skip
- If `/toxic-opinion` unavailable → inform user and skip

**Step 5 — Present findings:**
```
SPEC ANALYSIS

Ambiguities: X | Missing sections: Y | Assumptions: Z

[findings list]

Open questions:
[numbered list needing user input]

INPUT_VALIDATION gate:
- Answer open questions or accept assumptions
- Confirm spec is sufficient to proceed

When ready: /bergant-workflow:project-init complete INPUT_VALIDATION
```

---

## PRD

**Goal:** Structured product document with market context.

Read `docs/REQUIREMENTS.md` first.

**Step 1 — Proactive PM Review.** Before writing user stories, analyze the spec as a senior product manager:
- **Blind spot analysis:** What did the user NOT mention that's critical for this type of product? (onboarding, error recovery, edge cases in core flows, analytics, retention hooks)
- **Needs clarification:** Ask 3-7 probing questions that reveal unstated assumptions or unconsidered scenarios. Frame as "Have you thought about...?" not "You forgot..."
- **Feature suggestions:** Propose 3-5 improvements or features the user likely hasn't considered, based on the product domain and target users. For each: what it solves, effort (S/M/L), and whether it's MVP or post-MVP
- **Risk flags:** Identify product risks — what could make users abandon the product, what's the weakest part of the flow, where will support burden concentrate
- **Present findings and wait for user response** before proceeding. Update requirements based on their answers.

**Step 2 — User stories** with acceptance criteria, MoSCoW prioritization:
- Must Have = MVP (absolute minimum for launch)
- Should Have = v1.1
- Could Have = nice-to-have
- Won't Have = explicitly out of scope

**Step 3 — Web research** (interactive, optional):
- Ask user whether to research competitors/market (suggest top-5 by default)
- If yes and WebSearch is available → launch `Agent(general-purpose)` with WebSearch for competitor analysis
- Summarize: what competitors do well, market gaps, differentiation opportunities
- If user declines or WebSearch unavailable → skip, note in docs

**Step 4 — Legal & compliance assessment** (interactive):
- Identify legal risks relevant to the project (data privacy, platform ToS, industry regulations, liability)
- Research applicable regulations based on target market/users (GDPR, CCPA, industry-specific)
- If WebSearch is available → launch `Agent(general-purpose)` to research current legal requirements for the domain
- Present risks as a table: risk | impact | what's needed for MVP | what can wait
- Ask user which items to include as MVP requirements vs post-MVP
- Add approved items to PRD as "Legal & Compliance Requirements" section

**Step 5 — Second opinion** (IMPORTANT — always ask before presenting final PRD):
- **You MUST ask the user:** "Want to run `/toxic-opinion` for a critical review of the PRD before approval?"
- Do NOT skip this question. Do NOT proceed to the gate without asking.
- If user agrees and `/toxic-opinion` skill is available → invoke it with: "Critically evaluate this PRD. Right problem? Realistic MVP? What's missing? What fails day 1?"
- Synthesize findings into the PRD
- If user declines → skip
- If `/toxic-opinion` unavailable → inform user and skip

**Step 6 — Generate `docs/prd.md`:**
```markdown
# Product Requirements Document

## Vision
<what and why — one paragraph>

## Target Users
<personas with goals and pain points>

## Market Research
<competitors, gaps, differentiation — or "Skipped by user request">

## User Stories

### Must Have (MVP)
- US-1: As a <user>, I want <goal> so that <benefit>
  - AC: <acceptance criteria>

### Should Have
...

### Could Have (post-MVP)
...

## Key Flows
<main user journeys — numbered steps>

## Legal & Compliance Requirements
### MVP
<items needed before real users — data privacy, platform rules, disclaimers>
### Post-MVP
<items needed before scaling — DPAs, detailed legal review, tax compliance>

## Success Metrics
<measurable criteria>

## Out of Scope (v1)
<explicitly excluded items>
```

**Step 7 — Present** summary with key decisions needed (scope trade-offs, MVP boundaries, legal risks).

**STOP.** Gate: `When ready: /bergant-workflow:project-init complete PRD`

Suggest `/compact` before next phase.

---

## ARCHITECTURE

**Goal:** Design the system, choose tech stack, analyze risks.

Read `docs/REQUIREMENTS.md` and `docs/prd.md` first.

**Step 1 — Senior Architect Advisory.** Before designing, analyze requirements and **interview the user** as a senior architect. Do NOT just list missing concerns — ask structured questions with options, trade-offs, and recommendations. The user should make informed decisions, not discover gaps later.

**1a. Architecture fit analysis** (present, don't ask):
- Given the product's scale, team size, and constraints — what architecture pattern fits best? (monolith, modular monolith, microservices, serverless). Explain why, not just what.
- **Tech suggestions:** Propose technologies or patterns the user may not know about that solve their specific problems better.
- **Premature complexity check:** Flag anything in the requirements that might lead to over-engineering. Suggest simpler alternatives.
- **Scalability blind spots:** What will break first when the product grows? What's cheap to fix now but expensive later?

**1b. Architect questionnaire** (ask the user — present options with recommendations for each):
For each question: explain what it is in simple terms, present 2-3 options with trade-offs, give a clear recommendation, and explain why. Questions should cover at minimum:
- **Frontend architecture pattern:** FSD (Feature-Sliced Design) vs flat components vs Atomic Design vs domain-driven. **Default recommendation: FSD-lite** — 3 layers: `app/` (routes), `modules/` (features, isolated), `shared/` (ui, lib, types). Strict import rule: modules never import from each other. Simpler than full FSD (no slices/segments subdivision), scales well with Next.js App Router.
- **ORM choice:** e.g., TypeORM vs Drizzle vs Prisma — which fits the project's data model and team
- **API contract strategy:** how backend and frontend share types — REST+OpenAPI, tRPC, shared package, GraphQL
- **Auth strategy:** JWT, session-based, OAuth — what fits the user count and security needs
- **Real-time updates:** polling, SSE, WebSocket — what the admin panel needs
- **Deployment topology:** where each component runs, why
- **Database migration strategy:** how schema evolves over time
- **Secrets management:** .env, Docker secrets, Vault — what fits the stage
- **Structured logging:** what it is, why it matters, which library
- **Caching strategy:** what to cache, invalidation approach, TTL strategy
- **Email/notification provider:** for transactional emails, alerts
- **Error handling & retry strategy:** for external API calls (AI providers, WhatsApp, etc.)
- **Linting & formatting:** Biome vs ESLint+Prettier vs oxlint — single tool vs ecosystem. Default recommendation: Biome (Rust-based, replaces both ESLint and Prettier, ~100x faster)
- **Database hosting:** self-hosted vs managed (Neon, Supabase, RDS) — trade-offs of cost, maintenance, backups, branching
- **Monorepo tooling:** pnpm workspaces vs Turborepo vs Nx — what fits the project size
- **Package manager:** pnpm vs npm vs yarn — speed, disk efficiency, monorepo support
- Add domain-specific questions based on the project's unique needs

**Present findings and wait for user answers** before proceeding to detailed design. Do NOT proceed until all questions are answered.

**Step 2 — Architecture Design:**
- System components and responsibilities
- Component interactions / data flow
- API contracts (endpoints, methods, request/response shapes)
- Data model (entities, relationships, storage)
- State management approach

**Step 3 — Technology Decisions:**
- Stack choices with justification (why X over Y)
- Key libraries and frameworks
- Present alternatives where multiple valid options exist — let user choose
- Trade-offs for each decision

**Step 4 — Deployment & Infrastructure:**
- Hosting strategy (options + recommendation)
- CI/CD pipeline
- Environment management (dev, staging, prod)
- Monitoring, logging, alerting

**Step 5 — Security Analysis:**
- Auth approach
- Data protection
- OWASP top-10 relevant risks
- Input validation strategy

**Step 6 — Robustness Checklist** (score 0-3 per area):

| Area | What to check |
|------|---------------|
| Error handling | External calls wrapped? Errors surface cleanly? |
| Concurrency | Race conditions? Thread safety? |
| Data integrity | Atomic writes? Consistent state on failure? |
| Performance | Blocking calls? Memory bounds? |
| Security | Input sanitized? No injection vectors? |
| Observability | Logging? Progress feedback? Actionable errors? |
| Testability | Logic separated from I/O? Pure functions? |
| Scalability | Bottlenecks? Horizontal scaling possible? |

Flag areas scoring 0–1 as required fixes.

**Step 7 — Corner Cases** that could break the system.

**Step 8 — Design System** (mandatory for projects with frontend):

This step produces design system documentation (`docs/design-system.md`, `docs/design-system/pages/`) and defines Storybook infrastructure — the single source of truth for all UI decisions.

8a. **Ask the user** about frontend stack preferences. Default recommendation: **Tailwind CSS v4 + shadcn/ui v4 + Radix UI**. If user wants a different stack — adjust accordingly. Always confirm before proceeding.

8b. **Run design agents and skills** to generate the design system. Execute in the order below — each step builds on the previous. All run via `Agent` tool in isolated subprocesses.

  **Phase 1 — Design Vision (ctrlship agents, `~/.claude/agents/`)**

  These 4 agents form a coordinated design team. Orchestration protocol: `~/.claude/rules/design-team.md`.
  Run sequentially — each agent's output is context for the next.

  1. **Brand Agent** (`brand-agent`) — FIRST. Establish brand direction: purpose, personality, voice, visual identity principles. If no existing brand: runs discovery questions with user. If brand exists: Executor mode (apply existing guidelines). Output: brand brief.
  2. **UX Agent** (`ux-agent`) — Interaction design: user flows, navigation patterns, WCAG 2.2 compliance, cognitive load analysis. Input: brand brief + PRD user stories. Output: interaction patterns, flow specs, accessibility requirements.
  3. **Visual Agent** (`visual-agent`) — Creative direction: color palette (OKLCH), typography pairing, spacing scale, motion/animation, dark mode preparation. Input: brand brief + UX patterns. Output: visual design tokens, creative brief.
  4. **UI Agent** (`ui-agent`) — Component architecture: compound components, design token layers (global/alias/component), 9-state coverage (empty/loading/partial/loaded/error/offline/stale/disabled/read-only), ARIA patterns, responsive framework. Input: all previous output. Output: component specs, token architecture.

  After all 4 agents: produce `BRIEF.md` artifact with consolidated design decisions. Present to user for approval before proceeding.

  **Phase 2 — Technical Design System (skills)**

  Run after Phase 1 is approved. Skills refine the vision into implementable specs.

  1. **Interface Design** (`/init`) — Initialize persistent design system in `.interface-design/system.md`. Takes Phase 1 output and converts to: spacing grid, color tokens, depth strategy, surface elevation, button heights, card padding. Choose design direction (e.g., "Precision & Density" for admin panels, "Warmth & Approachability" for consumer). This file auto-loads in future sessions — ensures consistency.
  2. **Vercel Composition Patterns** — Define component architecture patterns: compound components, context providers, explicit variants, controlled vs uncontrolled. Input: UI Agent component specs.
  3. **Vercel Web Design Guidelines** — Audit all design decisions against 100+ UX/accessibility rules: focus management, form interactions, animation, typography, touch targets, i18n. Flag violations.
  4. **Vercel React Best Practices** — Validate performance patterns for the chosen React/Next.js version: rendering, memoization, code splitting, server components.
  5. **Anthropic Frontend Design** (if installed) — Cross-check for generic AI aesthetics. Ensure distinctive, production-grade choices (avoid: overused fonts like Inter/Roboto, cliché purple gradients, predictable layouts).

  **Orchestration rules:**
  - Phase 1 agents produce BRIEF.md → user approves → Phase 2 skills execute
  - Each agent/skill runs in its own `Agent` subprocess — no context pollution
  - Pass only the relevant output between steps (brief, tokens, component specs), not raw conversation
  - If an agent or skill is not installed — skip it, note in docs. Never block on missing tools
  - Protected zones: existing design tokens from Phase 1 are sacred — Phase 2 skills can use and extend them but NEVER modify source values
  - Token budget warning: 4 agents + 5 skills is heavy. If context is limited, prioritize: Brand → Visual → UI Agent → Interface Design → Web Design Guidelines. Skip others.

8c. **Generate `docs/design-system.md`:**
```markdown
# Design System

## Frontend Stack
| Layer | Technology | Version |
|-------|-----------|---------|

## Design Tokens

All tokens are the single source of truth. Components MUST use tokens — no hardcoded values.

### Colors
| Token | Value | Usage |
|-------|-------|-------|
| --color-primary | | Main actions, links, focus rings |
| --color-primary-hover | | Hover state for primary |
| --color-secondary | | Supporting elements |
| --color-neutral-50..950 | | Text, borders, backgrounds (full scale) |
| --color-success | | Positive states, confirmations |
| --color-warning | | Caution states |
| --color-error | | Error states, destructive actions |
| --color-info | | Informational elements |

### Typography
| Token | Value | Usage |
|-------|-------|-------|
| --font-family | | Base font |
| --font-family-mono | | Code, data |
| --font-size-xs..3xl | | Scale: xs, sm, base, lg, xl, 2xl, 3xl |
| --font-weight-normal..bold | | normal, medium, semibold, bold |
| --line-height-tight..relaxed | | tight, normal, relaxed |

### Spacing
| Token | Value | Usage |
|-------|-------|-------|
| --space-1..16 | | Scale: 1(4px), 2(8px), 3(12px), 4(16px), 6(24px), 8(32px), 12(48px), 16(64px) |

### Border Radius
| Token | Value | Usage |
|-------|-------|-------|
| --radius-sm | | Small elements (badges, tags) |
| --radius-md | | Buttons, inputs |
| --radius-lg | | Cards, modals |
| --radius-full | | Circular elements (avatars) |

### Shadows / Elevation
| Token | Value | Usage |
|-------|-------|-------|
| --shadow-sm | | Subtle depth (cards at rest) |
| --shadow-md | | Elevated elements (dropdowns, popovers) |
| --shadow-lg | | Modals, overlays |

## Component Architecture
- Wrapper components: `src/shared/ui/` — thin wrappers over base library for consistent behavior
- Compound components for complex UI (forms, modals, data tables)
- Every component MUST use design tokens — no hardcoded color/spacing/radius values
- Storybook story required for each component before use in pages

## Component Catalog

For each shared component — name, purpose, variants, states:

### <ComponentName>
- **When to use:** <guidance — when this component is the right choice>
- **Variants:** <e.g., primary, secondary, ghost, destructive>
- **States:** default, hover, active, focus, disabled, loading, error
- **Tokens used:** <which design tokens this component consumes>
- **Accessibility:** <keyboard navigation, ARIA requirements>

## Page Wireframes
Text-based wireframes for key pages live in `docs/design-system/pages/<page-name>.md`.
Each wireframe describes layout, components used, responsive behavior, and state transitions.
Wireframes MUST be approved before page implementation begins.

## Patterns
- Mobile-first responsive design
- <other patterns from agents/skills output>

## Accessibility
- WCAG 2.1 AA target
- <key rules from Web Design Guidelines>

## Storybook
- Every shared component gets a story with all variants and states
- Stories are living documentation and visual regression baseline
- Page-level stories for key flows (composition of components)
- Storybook is set up in Phase 1 of development plan
```

8d. **Generate page wireframes.** For each key flow from `docs/prd.md`, create `docs/design-system/pages/<page-name>.md`:
```markdown
# <Page Name>

## Purpose
<what the user accomplishes on this page>

## Layout
<text description of layout structure — what goes where>
<ASCII wireframe if helpful>

## Components Used
- <ComponentName> — <role on this page>
- ...

## States
- **Loading:** <what the user sees while data loads>
- **Empty:** <what the user sees when there's no data>
- **Error:** <what the user sees on failure>
- **Populated:** <normal state with data>

## Responsive Behavior
- **Mobile (< 768px):** <what changes>
- **Tablet (768-1024px):** <what changes>
- **Desktop (> 1024px):** <full layout>

## Interactions
- <user action> → <system response>
```

8e. **Storybook.** Confirm with user: Storybook will be configured in Phase 1 of PLANNING. Each base component will have a story file with all variants and states. This provides a visual preview and living documentation before components are used in pages.

8f. **Present design system summary** to user for review. Design decisions (tokens, component catalog, page wireframes, Storybook approach) must be approved before proceeding to architecture doc generation.

**Step 9 — Second opinion** (IMPORTANT — always ask):
- **You MUST ask the user:** "Want to run `/toxic-opinion` for a critical review of the architecture?"
- Do NOT skip this question. Do NOT proceed to the gate without asking.
- If user agrees and `/toxic-opinion` skill is available → invoke it with: "Critically evaluate this architecture. What breaks under load? Over-engineered parts? Security holes? Weakest component? Better alternatives?"
- Synthesize findings into `docs/architecture.md`
- If user declines → skip
- If `/toxic-opinion` unavailable → inform user and skip

**Step 10 — Generate `docs/architecture.md`:**
```markdown
# Architecture & Technical Design

## System Overview
<component diagram description — what talks to what>

## Components
### <Component Name>
- Responsibility: ...
- Technology: ...
- Interfaces: ...

## Data Model
<entities, relationships, storage strategy>

## API Design
<key endpoints with contracts>

## Technology Stack
| Layer | Technology | Version | Why |
|-------|-----------|---------|-----|

## Deployment & Infrastructure
<hosting, CI/CD, environments, monitoring>

## Security
<auth, data protection, risk mitigations>

## Robustness Scores
| Area | Score | Notes |
|------|-------|-------|

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|

## Corner Cases
- CC-1: ...

## Technical Warnings & Deferred Decisions
Items that are intentionally deferred from MVP but MUST be addressed before scaling. This section serves as a living tech debt backlog — review it before each major version.

| # | Item | Current State (MVP) | Target State | When to Address | Impact if Ignored |
|---|------|--------------------|--------------|-----------------|--------------------|
| TW-1 | ... | ... | ... | ... | ... |

## Design System
<reference to docs/design-system.md — do not duplicate, link only>
```

**Step 11 — Present** findings. Where multiple approaches exist, frame as options with trade-offs. Ask user to choose.

**STOP.** Gate: `When ready: /bergant-workflow:project-init complete ARCHITECTURE`

Suggest `/compact` before next phase.

---

## PLANNING

**Goal:** Break implementation into vertical slices with atomic subtasks.

Read `docs/prd.md` and `docs/architecture.md` first.

**Step 1 — Vertical Slices:**
- Organize by user-facing features, not technical layers
- Phase 1 = absolute minimum (core flow works end-to-end, minimal UI)
- Phase 1 MUST include design system infrastructure: Storybook setup, design tokens configuration, base component scaffolding with stories
- Each subsequent phase delivers a working increment
- Visual polish / design refinements = last phase
- Post-MVP features = separate section (discussed but not planned in detail)

**Step 2 — For each phase,** create `docs/plan/phase-N.md`:
```markdown
# Phase N: <Name>

## Goal
<what this phase delivers — user-visible result>

## Prerequisites
- Phase N-1 completed
- <external dependencies if any>

## Subtasks
- [ ] N.1: <atomic task> [S/M/L]
  - DoD: <definition of done — what to verify>
- [ ] N.2: ...

## Acceptance Criteria
- <what "done" looks like for this phase>
```

**Step 3 — Subtask rules:**
- Each subtask is independently implementable
- Clear DoD (what to verify when done)
- Size: S (< 1hr), M (1-3hr), L (3-8hr)
- No XL tasks — break them down further
- Include setup/infrastructure tasks in Phase 1
- New UI components → story first, then use in pages (component-first approach)
- Page wireframe (`docs/design-system/pages/<page>.md`) must exist before page implementation

**Step 4 — Second opinion** (IMPORTANT — always ask):
- **You MUST ask the user:** "Want to run `/toxic-opinion` for a critical review of the development plan?"
- Do NOT skip this question. Do NOT proceed to the gate without asking.
- If user agrees and `/toxic-opinion` skill is available → invoke it with: "Critically evaluate this development plan. Wrong phase order? Missing tasks? Unrealistic scope per phase? What will cause rework?"
- Synthesize findings into plan files
- If user declines → skip
- If `/toxic-opinion` unavailable → inform user and skip

**Step 5 — Present** the full plan. Discuss phase boundaries and priorities.

**STOP.** Gate: `When ready: /bergant-workflow:project-init complete PLANNING`

Suggest `/compact` before next phase.

---

## JIRA_SYNC

**Goal:** Push plan structure to Jira.

**Prerequisite check:** Verify that Jira MCP tools (`mcp__atlassian__*`) are available. If not — tell the user Jira sync is unavailable, mark phase as `completed` with note "skipped: Jira MCP not available", and advance to FINALIZE.

All Jira operations MUST go through Agent (never call MCP Jira tools in main context — responses bloat context). Use jira-ops skill patterns.

**Step 1 — Ask user for:**
- Jira project key (e.g., "KAN")
- Confirm or provide Jira Cloud ID (check `config.jiraCloudId` in state file first; if missing, look up via `mcp__atlassian__*` or ask user)
- Save both to `config` in state file for reuse

**Step 2 — Create structure:**
- **Epic** → project name (summary from state file)
- **Task** (one per phase) → linked to Epic as child
- **Sub-task** (one per atomic subtask) → linked to parent Task

**Step 3 — For each item,** launch Agent with jira-ops patterns:
```
Create Jira [Epic|Task|Sub-task] using mcp__atlassian__createJiraIssue with cloudId from state config.
Project: <key>
Type: <Epic|Task|Sub-task>
Summary: <name>
Description: <from plan file>
Parent: <parent key if Task or Sub-task>
Return ONLY: created issue key and summary, or error message.
```

**Step 4 — Update plan files** with Jira keys (e.g., `- [ ] KAN-15: N.1: Setup Express server`).

**Step 5 — Present** summary: Epic key, number of tasks/subtasks created.

**STOP.** Gate: `When ready: /bergant-workflow:project-init complete JIRA_SYNC`

Suggest `/compact` before next phase.

---

## FINALIZE

**Goal:** Generate project knowledge file and wrap up.

**Step 1 — Generate or update `CLAUDE.md`** in project root:

If `CLAUDE.md` already exists, **merge** — do not overwrite. Add a `## Project Init` section (or update it if present) with the content below. Preserve all existing sections untouched. If CLAUDE.md does not exist, create it with this template:

```markdown
# <Project Name>

## Overview
<one paragraph — what the project does and why>

## Tech Stack
<key technologies from architecture.md>

## Project Structure
<main directories and their purpose>

## Documentation
- `docs/REQUIREMENTS.md` — extracted and clarified requirements
- `docs/prd.md` — product requirements with user stories
- `docs/architecture.md` — architecture, tech stack, security, deployment
- `docs/plan/phase-*.md` — development phases with atomic subtasks

## Key Decisions
<top 3-5 architectural/product decisions and their rationale>

## Development Approach
- MVP-first with vertical slices
- Visual polish in final phase
- Phase 1 delivers: <what>
```

Keep CLAUDE.md concise — reference docs for details, don't duplicate.

**Step 1b — Ensure `.gitignore`.** Create `.gitignore` in the project root if missing, or
merge these entries into the existing one (never duplicate lines). This prevents secrets and
transient orchestration files from ever being committed:

```gitignore
# Secrets & env — NEVER commit
.env
.env.*
!.env.example
*.key
*.pem
secrets/

# Claude Code local config & agent state
.claude/

# Orchestration state files (transient)
docs/spec-state.json
.lifecycle-state.json

# Dependencies & build output
node_modules/
dist/
build/
coverage/

# Logs & OS / editor junk
*.log
.DS_Store
.idea/
.vscode/
```

Adjust the build/deps block to the project's actual stack (from `docs/architecture.md`).
If any of these files are already tracked in git, warn the user and suggest
`git rm --cached <file>` so they stop being committed.

**Step 2 — Update state** → all phases completed.

**Step 3 — Clean up state file.** Delete `docs/spec-state.json` — it was a transient orchestration artifact. All decisions are persisted in docs and CLAUDE.md.

**Step 4 — Display summary:**
```
PROJECT INIT — COMPLETE

Generated:
- docs/REQUIREMENTS.md
- docs/prd.md
- docs/architecture.md
- docs/plan/phase-1.md ... phase-N.md
- CLAUDE.md (created / updated)

Jira: Epic <key> → N tasks, M subtasks (or "skipped")

Next: use /bergant-workflow:lifecycle start <first-task-key> to begin development.
```
