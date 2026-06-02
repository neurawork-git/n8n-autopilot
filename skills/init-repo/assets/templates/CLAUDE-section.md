<!-- n8n-autopilot:start -->
## n8n-autopilot

This repo uses the **n8n-autopilot** Claude Code plugin. Workflows are TypeScript (Decorator format)
— never hand-write n8n JSON. (Section managed by `/n8n-autopilot:init-repo` — edits between the
markers are overwritten on re-run; put repo-specific notes outside the markers.)

### Entry points
- Build a workflow: `/n8n-autopilot:build-workflow "description"`
- Deploy a file: `/n8n-autopilot:deploy <name>.workflow.ts`
- Test a non-HTTP trigger (schedule/manual/error): `/n8n-autopilot:test-manual <workflowId>`
- Give feedback: `/n8n-autopilot:feedback` (review → PII-redact → push)
- Find credentials / projects: `/n8n-autopilot:find-credential <pat>` · `/n8n-autopilot:find-project`

### Auto-Reactions on SessionStart
SessionStart hooks may print `AUTOPILOT_ACTION_REQUIRED: <slash-command>` — run that exact command
immediately, without asking (safe + idempotent). `INFO:` lines are informational only (surface, do
not auto-run) — e.g. pending feedback (`check-feedback-pending.sh`), stale inventory.

### Workflow design quality (the workflow-reviewer enforces this)
- **Native-first** — prefer `IF`/`Switch`/`Filter`/`Set` over Code nodes for branching/mapping.
- **No silent failures** — never `continueOnFail: true` / `onError: continue` without an error branch.
- **Memory** — Code nodes iterating large DB result sets cause OOM; use `SplitInBatches`/pagination.
- **Descriptions** present (`@workflow` + key nodes); **no overlapping** node positions.

Auto-activated guidance skills: `n8n-orchestration-patterns` (fan-out/fan-in, parallel sub-workflows),
`n8n-structured-extraction` (LLM extraction via JSON schema), `n8n-code-javascript` / `n8n-code-python`.

### NEVER (enforced by hooks)
- Never call the n8n REST API directly (curl/fetch/HTTP node) — exception: `/api/v1/data-tables` via
  `/n8n-autopilot:data-tables`.
- Never delete workflows without explicit user confirmation.
- Never hand-write workflow JSON — always Decorator-TS.
<!-- n8n-autopilot:end -->
