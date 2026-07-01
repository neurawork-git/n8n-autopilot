# n8nac Command Catalogue (annotated)

The authoritative command surface is the **[`n8nac-reference`](../../skills/n8nac-reference/SKILL.md)**
skill (raw `--help` tree — "if it isn't in `reference.md`, it doesn't exist") and the curated
**[`n8nac-cheatsheet`](../../skills/n8nac-cheatsheet/SKILL.md)**. This file keeps the annotated,
intent-grouped list (notes/flags that aren't in raw `--help`). Also see [OVERVIEW.md](../OVERVIEW.md).

## ALWAYS use n8nac (PRIMARY)

- Node research: n8nac MCP tools (`search_n8n_knowledge`, `get_n8n_node_info`, `search_n8n_docs`, `search_n8n_workflow_examples`)
- Validate (local): `npx n8nac skills validate <file>` — agent pipelines: `--strict --json` for structured output
- Deploy + verify: `npx n8nac push <file> --verify` — push and immediately validate remote state
- Test: `npx n8nac test <id> --data '...'` (or `--query` for GET webhooks; `--prod` for production URL — workflow must be active)
- Test plan: `npx n8nac test-plan <id> --json` — infer trigger type + suggested payload before testing
- Activate: `npx n8nac workflow activate <id>`
- Deactivate: `npx n8nac workflow deactivate <id>`
- Credentials: `npx n8nac credential list/get/create/delete/schema <type>`
- Credential recipes (n8nac >= 2.2): `npx n8nac credentials recipes/inventory/starter-kits --json` — shared catalogue (openai-native, slack-oauth, postgres, …); `npx n8nac credentials ensure <recipeId>` creates from recipe; `npx n8nac credentials test <id-or-recipeId>` verifies live
- Executions: `npx n8nac execution list/get`
- Workflow URL resolution: `npx n8nac workflow present <id> --json` — never string-concat `<host>/workflow/<id>`

## Operations (all via n8nac CLI)

- Health check: `bash scripts/setup-check.sh`
- List/search workflows: `npx n8nac list` / `npx n8nac find <query>` — **default excludes archived**; use `--include-archived` for all, `--only-archived` for archive-only; `--json --search --sort --limit --local --remote` for scripted/agent use
- **Archived workflows are read-only** — `push` is rejected. No code-fix loop; unarchive (n8n UI) or recreate first.
- Get workflow details: `npx n8nac pull <workflowId>`
- Deploy template: `npx n8nac skills examples search/list/info/download <id>` → `npx n8nac push`
- Execution history: `npx n8nac execution list --workflow-id <id>`
- Execution details: `npx n8nac execution get <execId> --include-data`
- Community node search: n8nac MCP `search_n8n_knowledge` + `docs/COMMUNITY_NODES.md`
- Workflow fix after error: Claude reads error → fixes .workflow.ts → `n8nac skills validate` → `n8nac push --verify` → `n8nac test`
- Conflict resolution: `npx n8nac resolve <workflowId>` — resolve local/remote conflict before push
- Remote validation: `npx n8nac verify <workflowId>` — validate remote workflow against local schema
- Credential check: `npx n8nac workflow credential-required <id>` — exit 0 = all present, exit 1 = missing
- Remote state fetch: `npx n8nac fetch <workflowId>` — explicitly fetch remote state
- Format conversion: `npx n8nac convert <file>` / `npx n8nac convert-batch <dir>` — JSON ↔ TypeScript
- AI context: `npx n8nac update-ai` — regenerate AGENTS.md + AI context
- Multi-environment: `npx n8nac env list/add/update/pin/remove` — environment management (multiple n8n instances per repo)
- Switch active environment: `npx n8nac env use <name>` (alias: `env pin <name>`) — **blocked by env-gate clobber-guard; pin via `N8NAC_ENVIRONMENT` instead** (see [../rules/gates.md](../rules/gates.md))
- Read workspace context: `npx n8nac workspace status --json` (alias `get`) — read-only, shows active bound env + project; mutate via `env add` / `env update` / `env use`
- Setup (first config): `npx n8nac setup --mode <managed-local|connect-existing|generation-only>` (mode list: `npx n8nac setup-modes`). `init` / `init-auth` / `init-project` from n8nac < 2.2 are **removed** — never use.
- Node reference: `npx n8nac skills node-schema <name>` — quick TypeScript snippet (`--json` for structured agent output); `skills node-info <name> --json` — full node info; `skills related <query>` — related nodes; `skills guides` — tutorials; `skills list --nodes/--docs/--guides` — enumeration
- `@workflow` decorator: optional `description` field (round-trip-capable, appears in n8n UI and `n8nac list` output)

## Workflow design quality (enforced by `workflow-reviewer`)

The `workflow-reviewer` agent checks 15 points incl. design-quality: native-first (prefer
`IF`/`Switch`/`Filter`/`Set` over Code nodes), no silent failures (`continueOnFail`/`onError:continue`
without an error branch), memory/large-data (Code nodes on big DB result sets → OOM; use
`SplitInBatches`/pagination), descriptions present, no overlapping node positions. Deeper authoring
rules stay with the companion `n8n-architect` plugin.

Auto-activated workflow-pattern guidance skills (org-learned, concrete examples):
- `n8n-orchestration-patterns` — fan-out/fan-in, parallel sub-workflows (branch-split trap,
  `executionOrder: v0`, DataTable fan-in), synchronous batch + fast-return webhook.
- `n8n-structured-extraction` — LLM extraction/classification via a real JSON schema (Information
  Extractor / Text Classifier), never Agent+prompt.
- `/n8n-autopilot:data-tables` — also documents the upsert node shape (3-part requirement) + usage
  patterns (fan-in store, idempotency/dedup, error rows).
