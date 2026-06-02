# Lifecycle State Schema

File: `.lifecycle-state.json`

```json
{
  "task": "<task-name>",
  "branch": "<current git branch>",
  "startedAt": "<ISO timestamp>",
  "currentStep": "CONTEXT_CHECK",
  "awaitingCompact": true,
  "scopeApprovedAt": "<ISO timestamp — set when user runs /lifecycle complete SCOPE>",
  "codexOpinionIncorporated": false,
  "codexFindings": [],
  "scopeNotes": {
    "approvedScope": []
  },
  "steps": {
    "CONTEXT_CHECK": { "status": "in_progress", "gate": "auto" },
    "SCOPE": {
      "status": "pending",
      "gate": "user",
      "gateDescription": "Product approval before technical planning"
    },
    "PLAN": { "status": "pending", "gate": "auto" },
    "COMPONENTS": {
      "status": "pending",
      "gate": "user",
      "gateDescription": "Approve components in Storybook before feature implementation",
      "components": []
    },
    "IMPLEMENT": {
      "status": "pending",
      "gate": "auto",
      "subtasks": []
    },
    "VERIFY": {
      "status": "pending",
      "gate": "user",
      "gateDescription": "Manual browser testing by user"
    },
    "TEST": { "status": "pending", "gate": "auto" },
    "REVIEW": {
      "status": "pending",
      "gate": "user",
      "gateDescription": "User reviews findings and approves fixes"
    },
    "DOCUMENT": { "status": "pending", "gate": "auto" },
    "CLOSE": {
      "status": "pending",
      "gate": "user",
      "gateDescription": "User reviews PR before merge"
    }
  }
}
```

Step order: CONTEXT_CHECK → SCOPE → PLAN → COMPONENTS → IMPLEMENT → VERIFY → TEST → REVIEW → DOCUMENT → CLOSE

## Optional top-level fields (post-compact context recovery)

These fields survive `/compact` and give the next session enough semantic anchors to resume without re-deriving decisions.

| Field | Type | Set when | Purpose |
|-------|------|----------|---------|
| `scopeApprovedAt` | ISO timestamp | User runs `/lifecycle complete SCOPE` | Proof that SCOPE gate passed; ordering |
| `codexOpinionIncorporated` | boolean | `/toxic-opinion` ran during SCOPE and findings merged into approved scope | Guards against re-asking Codex post-compact |
| `codexFindings` | string[] | Approved SCOPE — distill Codex second-opinion diffs into short semantic tags | Each tag = anchor to rehydrate full context in PLAN (e.g., `"schema_enum_fix_required"`, `"split_transactions"`) |
| `scopeNotes.approvedScope` | string[] | Approved SCOPE | Bullet list of concrete scope items the user confirmed; source of truth for PLAN and IMPLEMENT |

**Tag naming convention for `codexFindings`:**
- Lowercase, snake_case, ≤4 words
- Action- or object-oriented (`split_transactions`, `pii_redaction`, not `good_idea`)
- One tag = one implementable decision — if a tag unpacks to multiple actions, split it
