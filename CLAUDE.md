# n8n Workflow Development — n8n-autopilot Plugin

This repo uses the **n8n-autopilot plugin** for Claude Code.
Workflows are TypeScript (Decorator format). Never write n8n JSON by hand.

> **You are in the INTERNAL repo (`nashtrader/n8n-autopilot-internal`).** The matching public repo is `nashtrader/n8n-autopilot` at `~/Documents/Repositories/n8n-autopilot-public/`. When the user asks to release / publish / ship to public, follow [`RELEASE_PROCESS.md`](RELEASE_PROCESS.md) — it is the authoritative manual procedure for syncing internal → public.

## Setup

**Brand-new repo? One command:**
→ `/n8n-autopilot:init-repo [target-dir]` — scaffolds dir layout + CLAUDE.md/README/.gitignore/.mcp.json/.env.example, runs `n8nac init`, pulls schemas, verifies.

**Manual (if you prefer step-by-step):**
1. Install plugin: `claude plugin marketplace add nashtrader/n8n-autopilot && claude plugin install n8n-autopilot@n8n-autopilot`
2. Copy MCP config: `cp "$(claude plugin path n8n-autopilot)/.mcp.json.example" .mcp.json`
3. `npx n8nac init` (non-interactive: `npx n8nac init-auth --yes && npx n8nac init-project --yes`) — writes `n8nac-config.json` (gitignored)
4. `/n8n-autopilot:pull-schemas` — populate `schemas/nodes/` (gitignored, instance-specific)
5. Verify: `bash scripts/setup-check.sh`

## Auto-Reactions on SessionStart

SessionStart hooks emit `AUTOPILOT_ACTION_REQUIRED: <slash-command>` lines when state is stale and an automated fix exists. When you see such a line in hook output, **run that exact slash-command immediately, without asking the user first** — these signals only fire when the action is safe and idempotent.

| Signal source | Hook? | Trigger | Auto-action |
|---|---|---|---|
| `check-schema-versions.sh` | direct (SessionStart) | Cached schema older than latest npm version | `/n8n-autopilot:pull-schemas --community-only --packages <list>` |
| `check-installed-nodes.sh` | indirect (called by `setup-check.sh` Section 7) | Community node installed on instance, no cached schema | `/n8n-autopilot:pull-schemas --community-only --packages <list>` |
| `check-credential-freshness.sh` | direct (SessionStart) | Workflow references credential ID that does not exist on instance | `/n8n-autopilot:sync-credentials --fix-workflows` |

Hard rule: parse the literal slash-command after `AUTOPILOT_ACTION_REQUIRED:` and execute it. Do not paraphrase, do not skip the `--packages` list, do not bundle multiple signals into one call — run each line as written.

Signals NOT auto-triggered (informational only): `check-inventory-freshness.sh` (`INFO:` prefix — surface to user, do not auto-regenerate; inventory regeneration is expensive).

## Entry Point

When the user asks to create, build, or scaffold a workflow:
→ `/n8n-autopilot:build-workflow "description"` — full pipeline incl. deploy
→ **NEVER write workflow code directly** — Phase 0 research via n8nac is mandatory.

## Deploy

→ `/n8n-autopilot:deploy <workflow-name>.workflow.ts`

## Tool Boundaries

### ALWAYS use n8nac (PRIMARY)
- Node research: n8nac MCP tools (`search_n8n_knowledge`, `get_n8n_node_info`, `search_n8n_docs`, `search_n8n_workflow_examples`)
- Validate (local): `npx n8nac skills validate <file>` — Agent-Pipelines: `--strict --json` für strukturierten Output
- Deploy + verify: `npx n8nac push <file> --verify` — push and immediately validate remote state
- Test: `npx n8nac test <id> --data '...'` (or `--query` for GET webhooks; `--prod` for production URL — workflow must be active)
- Test plan: `npx n8nac test-plan <id> --json` — infer trigger type + suggested payload before testing
- Activate: `npx n8nac workflow activate <id>`
- Deactivate: `npx n8nac workflow deactivate <id>`
- Credentials: `npx n8nac credential list/get/create/delete/schema <type>`
- Executions: `npx n8nac execution list/get`

### Operations (all via n8nac CLI)
- Health check: `bash scripts/setup-check.sh`
- List/search workflows: `npx n8nac list` / `npx n8nac find <query>` — **default excludes archived**; use `--include-archived` for all, `--only-archived` for archive-only; `--json --search --sort --limit --local --remote` for scripted/agent use
- **Archivierte Workflows sind read-only** — `push` wird abgelehnt. Kein Code-Fix-Loop; erst unarchivieren (n8n UI) oder neu erstellen.
- Get workflow details: `npx n8nac pull <workflowId>`
- Deploy template: `npx n8nac skills examples search/list/info/download <id>` → `npx n8nac push`
- Execution history: `npx n8nac execution list --workflow <id>`
- Execution details: `npx n8nac execution get <execId> --include-data`
- Community node search: n8nac MCP `search_n8n_knowledge` + `docs/COMMUNITY_NODES.md`
- Workflow fix after error: Claude reads error → fixes .workflow.ts → `n8nac skills validate` → `n8nac push --verify` → `n8nac test`
- Conflict resolution: `npx n8nac resolve <workflowId>` — resolve local/remote conflict before push
- Remote validation: `npx n8nac verify <workflowId>` — validate remote workflow against local schema
- Credential check: `npx n8nac workflow credential-required <id>` — exit 0 = all present, exit 1 = missing
- Remote state fetch: `npx n8nac fetch <workflowId>` — explizit Remote-State abrufen
- Format conversion: `npx n8nac convert <file>` / `npx n8nac convert-batch <dir>` — JSON ↔ TypeScript
- AI-Kontext: `npx n8nac update-ai` — AGENTS.md + AI-Kontext regenerieren
- Multi-Environment: `npx n8nac env list/add/update/pin/remove` — Environment-Management (mehrere n8n-Instanzen pro Repo)
- Aktives Environment wechseln: `npx n8nac env use <name>` (alias: `env pin <name>`)
- Workspace ↔ Instanz-Binding: `npx n8nac workspace pin-instance` / `clear-instance` / `status`
- Node-Referenz: `npx n8nac skills node-schema <name>` — schnelles TypeScript-Snippet (`--json` für strukturierten Agent-Output); `skills node-info <name> --json` — vollständige Node-Info; `skills related <query>` — verwandte Nodes; `skills guides` — Tutorials; `skills list --nodes/--docs/--guides` — Enumerierung
- `@workflow` Decorator: optionales `description`-Feld (Round-trip-fähig, erscheint in n8n UI und `n8nac list`-Output)

### MCP Access Lifecycle (Workflows mit mcpTrigger) — MANUELL

Workflows, die `@n8n/n8n-nodes-langchain.mcpTrigger` enthalten, exponieren einen MCP-Endpoint.
Dieser Endpoint ist NUR nach Publish in der n8n-UI erreichbar. `n8nac push` erzeugt einen neuen
Draft — die bisher publizierte Version bleibt stehen, der MCP-Endpoint kann gegenüber dem
neuen Draft veraltet sein.

**Regel:** Nach jedem Push/Update eines Workflows mit `mcpTrigger`:
1. n8n-UI öffnen: `<n8n_host>/workflow/<workflowId>`
2. "Publish"-Button klicken
3. User bestätigt Publish-Status im Completion Report

n8nac kann nicht publishen. `deploy` skill und Phase 2 (Path D) der `build-workflow` pipeline
zeigen einen prominenten Hinweis statt automatischem Re-Publish.

### Non-HTTP-Trigger Testing — MANUELL

`n8nac test` kann nur Webhook-/Chat-/Form-Trigger auslösen. Für `schedule`, `manual`, `errorTrigger`:

1. n8n-UI öffnen: `<n8n_host>/workflow/<workflowId>`
2. "Execute Workflow"-Button klicken
3. User meldet `execution-id` an Claude
4. Claude inspiziert via `npx n8nac execution get <id> --include-data`

Die `build-workflow` pipeline (Path B) stoppt automatisch und prompted den User entsprechend.

### DataTable Lifecycle (curl carve-out)

n8nac has no `datatable` subcommand. Managing DataTable resources (create/list/seed/drop tables, columns, rows) is done via the n8n public REST API at `/api/v1/data-tables`. The PreToolUse curl-block has an explicit carve-out for this path only.

→ Use `/n8n-autopilot:data-tables` skill — it documents every endpoint and provides ready-to-paste curl recipes (incl. heredoc-safe JSON for umlauts on Windows).

### NEVER do these (enforced by hooks)
- Never call n8n REST API directly (curl, fetch, HTTP Request node) — **exception:** `/api/v1/data-tables` via the `data-tables` skill
- Never delete workflows without explicit user confirmation
- Never write workflow JSON by hand — always Decorator-TS format
