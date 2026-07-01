# {{REPO_NAME}} — n8n Workflows

This repo uses the **n8n-autopilot plugin** for Claude Code.
Workflows are TypeScript (Decorator format). Never write n8n JSON by hand.

## Setup

If you are starting from scratch, the plugin's `init-repo` skill has already scaffolded this layout. To re-verify:

```
/n8n-autopilot:check-mcps
```

(SessionStart hook also runs the same check automatically when you open Claude Code in this repo.)

## Entry Point

When you ask Claude to create, build, or scaffold a workflow:
→ `/n8n-autopilot:build-workflow "description"` — full 3-phase pipeline (Research → Write+Validate → Deploy+Test)
→ **Never write workflow code directly** — Phase 0 research via n8nac is mandatory.

## Deploy

→ `/n8n-autopilot:deploy <workflow-name>.workflow.ts`

## Auto-Reactions on SessionStart

SessionStart hooks emit `AUTOPILOT_ACTION_REQUIRED: <slash-command>` lines when state is stale and an automated fix exists. When you see such a line in hook output, **run that exact slash-command immediately, without asking the user first** — these signals only fire when the action is safe and idempotent.

| Signal source | Hook? | Trigger | Auto-action |
|---|---|---|---|
| `check-schema-versions.sh` | direct (SessionStart) | Cached schema older than latest npm version | `/n8n-autopilot:pull-schemas --community-only --packages <list>` |
| `check-installed-nodes.sh` | indirect (called by `setup-check.sh` Section 7) | Community node installed on instance, no cached schema | `/n8n-autopilot:pull-schemas --community-only --packages <list>` |
| `check-credential-freshness.sh` | direct (SessionStart) | Workflow references credential ID that does not exist on instance | `/n8n-autopilot:sync-credentials --fix-workflows` |

Hard rule: parse the literal slash-command after `AUTOPILOT_ACTION_REQUIRED:` and execute it. Do not paraphrase, do not skip the `--packages` list, do not bundle multiple signals into one call.

Signals NOT auto-triggered (informational only — surface to user, never auto-run):
- `check-inventory-freshness.sh` (`INFO:` prefix — do not auto-regenerate; inventory regeneration is expensive).
- `check-feedback-pending.sh` (`INFO:` prefix — unsynced autopilot feedback exists; offer `/n8n-autopilot:feedback`, do not auto-run — feedback needs user consent).

## Feedback Loop

A SessionEnd hook (`capture-feedback.sh`) silently records NON-PII friction signal counts from each
session to `.n8n-autopilot/feedback/events.ndjson` (gitignored). Run `/n8n-autopilot:feedback` to add
process feedback (a short interview), and `/n8n-autopilot:feedback sync` to push everything centrally
(creates a GitHub issue — explicit consent required). Auto-captured records carry only counts + the
repo basename; never customer data.

## Repo Layout

| Path | Purpose |
|------|---------|
| `workflows/` | `*.workflow.ts` files — your n8n workflows in Decorator-TS format |
| `schemas/nodes/` | Cached node schemas for offline validation (gitignored, run `/n8n-autopilot:pull-schemas` after first clone) |
| `data/` | Local data files used by workflows (CSV, JSON, etc.) |
| `docs/` | Workflow design docs, runbooks |

> **n8nac config:** Environment + instance config lives in user home (`~/n8nac-config.json` + `~/.n8n-manager/`) under n8nac >= 2.3 — NOT in this repo. Bind this repo to an n8n instance via `npx n8nac env add <name> --base-url <url> --workflows-path workflows`, then `printf '%s' "$N8N_API_KEY" | npx n8nac env auth set <name> --api-key-stdin`, then `npx n8nac env use <name>`. See [n8nac docs](https://www.npmjs.com/package/n8nac).

## Tool Boundaries

### ALWAYS use n8nac (PRIMARY)
- Node research: n8nac MCP tools (`search_n8n_knowledge`, `get_n8n_node_info`, `search_n8n_docs`, `search_n8n_workflow_examples`)
- Validate (local): `npx n8nac skills validate <file>` — Agent-Pipelines: `--strict --json`
- Deploy + verify: `npx n8nac push <file> --verify` — push and immediately validate remote state
- Test: `npx n8nac test <id> --data '...'` (or `--query` for GET webhooks; `--prod` for production URL — workflow must be active)
- Test plan: `npx n8nac test-plan <id> --json` — infer trigger type + suggested payload before testing
- Activate / deactivate: `npx n8nac workflow activate <id>` / `... deactivate <id>`
- Credentials: `npx n8nac credential list/get/create/delete/schema <type>`
- Executions: `npx n8nac execution list/get`

### Operations (all via n8nac CLI)
- Health check: `/n8n-autopilot:check-mcps` (or runs auto via SessionStart hook)
- List/search workflows: `npx n8nac list` / `npx n8nac find <query>` — **default excludes archived**; use `--include-archived` for all, `--only-archived` for archive-only; `--json --search --sort --limit --local --remote` for scripted/agent use
- **Archived workflows are read-only** — `push` is rejected. No code-fix-loop; unarchive in n8n UI or create new.
- Get workflow details: `npx n8nac pull <workflowId>`
- Deploy template: `npx n8nac skills examples search/list/info/download <id>` → `npx n8nac push`
- Execution history: `npx n8nac execution list --workflow-id <id>`
- Execution details: `npx n8nac execution get <execId> --include-data`
- Community node search: n8nac MCP `search_n8n_knowledge` (see also: `pull-schemas` skill, Stage 3 fallback)
- Workflow fix after error: read error → fix `.workflow.ts` → `n8nac skills validate` → `n8nac push --verify` → `n8nac test`
- Conflict resolution: `npx n8nac resolve <workflowId>` — resolve local/remote conflict before push
- Remote validation: `npx n8nac verify <workflowId>` — validate remote workflow against local schema
- Credential check: `npx n8nac workflow credential-required <id>` — exit 0 = all present, exit 1 = missing
- Remote state fetch: `npx n8nac fetch <workflowId>` — explicit remote-state fetch
- Format conversion: `npx n8nac convert <file>` / `npx n8nac convert-batch <dir>` — JSON ↔ TypeScript
- AI context: `npx n8nac update-ai` — regenerate `AGENTS.md` + AI context
- Multi-environment: `npx n8nac env list/add/update/pin/remove`
- Switch active environment: `npx n8nac env use <name>` (alias: `env pin`)
- Workspace status (read-only): `npx n8nac workspace status --json` — effective-context resolver
- Node reference: `npx n8nac skills node-schema <name>` (quick snippet, `--json` for agents); `skills node-info <name> --json` (full); `skills related <query>`; `skills guides`; `skills list --nodes/--docs/--guides`
- `@workflow` decorator: optional `description` field (round-trip-capable, appears in n8n UI and `n8nac list`)

### DataTable Lifecycle (curl carve-out)

n8nac has no `datatable` subcommand. Manage DataTable resources (create/list/seed/drop tables, columns, rows) via the n8n public REST API at `/api/v1/data-tables`. The PreToolUse curl-block has an explicit carve-out for this path only.

→ Use `/n8n-autopilot:data-tables` — documents every endpoint and provides ready-to-paste curl recipes (incl. heredoc-safe JSON for umlauts on Windows).

### MCP Access Lifecycle (workflows with mcpTrigger) — MANUAL

Workflows containing `@n8n/n8n-nodes-langchain.mcpTrigger` expose an MCP endpoint that is only reachable on the **published** version. `n8nac push` writes a new draft — the previously published version stays live, but the MCP endpoint may diverge from the new draft.

**Rule:** after every push/update of a workflow with `mcpTrigger`:
1. Open n8n UI: `<n8n_host>/workflow/<workflowId>`
2. Click "Publish"
3. User confirms publish status in the Completion Report

n8nac cannot publish. The `deploy` skill and Phase 2 (Path D) of `build-workflow` show a prominent notice instead of attempting an automatic re-publish.

### Non-HTTP-Trigger Testing — MANUAL

`n8nac test` can only fire webhook / chat / form triggers. For `schedule`, `manual`, `errorTrigger`:

1. Open n8n UI: `<n8n_host>/workflow/<workflowId>`
2. Click "Execute Workflow"
3. User reports the `execution-id` back to Claude
4. Claude inspects via `npx n8nac execution get <id> --include-data`

The `build-workflow` pipeline (Path B) stops automatically and prompts the user accordingly.

### NEVER do these (enforced by hooks)
- Never call n8n REST API directly (curl, fetch, HTTP Request node) — **exception:** `/api/v1/data-tables` via the `data-tables` skill
- Never delete workflows without explicit user confirmation
- Never write workflow JSON by hand — always Decorator-TS format
- Never set `continueOnFail: true` without explicit user request — masks silent failures
- Never use `HTTP`/`fetch`/`axios` in Code nodes — use the HTTPRequest node instead
