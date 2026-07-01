# Tool Boundaries — full reference

CLAUDE.md keeps only the non-discoverable rules (archived = read-only, never string-concat URLs,
removed commands, MCP-publish + non-HTTP-test detours, the hard NEVERs). This file holds the full
CLI catalog. Most of it is also covered, more current, by the **[`n8nac-cheatsheet`](../../skills/n8nac-cheatsheet/SKILL.md)**
and **[`n8nac-reference`](../../skills/n8nac-reference/SKILL.md)** skills — grep those first; treat
this list as a backstop.

## ALWAYS use n8nac (PRIMARY)
- Node research: n8nac MCP tools (`search_n8n_knowledge`, `get_n8n_node_info`, `search_n8n_docs`, `search_n8n_workflow_examples`)
- Validate (local): `npx n8nac skills validate <file>` — Agent-Pipelines: `--strict --json` für strukturierten Output
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
- Aktives Environment wechseln: `npx n8nac env use <name>` (alias: `env pin <name>`) — **nur via Clobber-Guard-Bypass, siehe [gates](../troubleshooting/gates.md)**
- Workspace-Kontext lesen: `npx n8nac workspace status --json` (alias `get`) — read-only, zeigt aktiv gebundenes Env + Projekt; Mutation erfolgt über `env add` / `env update` / `env use`
- Setup (Erstkonfiguration): `npx n8nac setup --mode <managed-local|connect-existing|generation-only>` (Modus-Liste: `npx n8nac setup-modes`). `init` / `init-auth` / `init-project` aus n8nac < 2.2 sind **entfernt** — niemals verwenden.
- Node-Referenz: `npx n8nac skills node-schema <name>` — schnelles TypeScript-Snippet (`--json` für strukturierten Agent-Output); `skills node-info <name> --json` — vollständige Node-Info; `skills related <query>` — verwandte Nodes; `skills guides` — Tutorials; `skills list --nodes/--docs/--guides` — Enumerierung
- `@workflow` Decorator: optionales `description`-Feld (Round-trip-fähig, erscheint in n8n UI und `n8nac list`-Output)

## MCP Access Lifecycle (Workflows mit mcpTrigger) — MANUELL

Workflows, die `@n8n/n8n-nodes-langchain.mcpTrigger` enthalten, exponieren einen MCP-Endpoint.
Dieser Endpoint ist NUR nach Publish in der n8n-UI erreichbar. `n8nac push` erzeugt einen neuen
Draft — die bisher publizierte Version bleibt stehen, der MCP-Endpoint kann gegenüber dem
neuen Draft veraltet sein.

**Regel:** Nach jedem Push/Update eines Workflows mit `mcpTrigger`:
1. URL via n8nac auflösen: `npx n8nac workflow present <workflowId> --json`
2. n8n-UI öffnen unter der URL aus dem Output
3. "Publish"-Button klicken
4. User bestätigt Publish-Status im Completion Report

n8nac kann nicht publishen. `deploy` skill und Phase 2 (Path D) der `build-workflow` pipeline
zeigen einen prominenten Hinweis statt automatischem Re-Publish.

## Non-HTTP-Trigger Testing — MANUELL

`n8nac test` kann nur Webhook-/Chat-/Form-Trigger auslösen. Für `schedule`, `manual`, `errorTrigger`:

→ **`/n8n-autopilot:test-manual <workflowId>`** bündelt den ganzen Detour (URL auflösen → auf
execution-id warten → Run inspizieren). Manuell sind die Schritte:

1. URL via n8nac auflösen: `npx n8nac workflow present <workflowId> --json`
2. n8n-UI unter dieser URL öffnen
3. "Execute Workflow"-Button klicken
4. User meldet `execution-id` an Claude
5. Claude inspiziert via `npx n8nac execution get <id> --include-data`

Die `build-workflow` pipeline (Path B) stoppt automatisch und prompted den User entsprechend.

## DataTable Lifecycle (curl carve-out)

n8nac has no `datatable` subcommand. Managing DataTable resources (create/list/seed/drop tables,
columns, rows) is done via the n8n public REST API at `/api/v1/data-tables`. The PreToolUse
curl-block has an explicit carve-out for this path only.

→ Use `/n8n-autopilot:data-tables` skill — it documents every endpoint and provides ready-to-paste
curl recipes (incl. heredoc-safe JSON for umlauts on Windows).

## Feedback Loop (capture + central feedback)

A `SessionEnd` hook (`scripts/capture-feedback.sh`) silently appends NON-PII friction signal counts
(an anchored signal taxonomy) from each session to `.n8n-autopilot/feedback/events.ndjson` in the
consumer repo (gitignored). A `SessionStart` probe (`scripts/check-feedback-pending.sh`) emits an
`INFO:` nudge when unsynced records exist.

- `/n8n-autopilot:feedback` (default = **review**) — one-shot: reviews the session (auto-captured
  signals + file-level design metrics from `workflows/*.workflow.ts` + a qualitative pass),
  LLM-redacts to neutral insights, runs the deterministic PII gate, shows the result, then pushes.
- `/n8n-autopilot:feedback interview` — manual Q&A only. `… show` — list pending. `… sync` — push only.
- **Push** = ONE labelled GitHub issue on `neurawork-git/n8n-autopilot-internal` via `gh issue create`
  (one path, no fallback). **Side-effecting + consent-gated**: shows every record, requires explicit
  confirmation. Live web-server ingestion = future TODO.
- **PII (defense-in-depth):** auto-capture stores only counts + repo basename. Before ANY push,
  `scripts/redact-check.js` deterministically BLOCKS unknown keys + free-text matching
  email/path/URL/long-digit/token/customer-name patterns — on top of the LLM redaction. No hook ever
  pushes; capture is local-only.

## Workflow design quality (enforced by `workflow-reviewer`)

The `workflow-reviewer` agent checks 15 points incl. design-quality:
native-first (prefer `IF`/`Switch`/`Filter`/`Set` over Code nodes), no silent failures
(`continueOnFail`/`onError:continue` without an error branch), memory/large-data (Code nodes on big
DB result sets → OOM; use `SplitInBatches`/pagination), descriptions present, no overlapping node
positions. Deeper authoring rules stay with the companion `n8n-architect` plugin.

Auto-activated workflow-pattern guidance skills (org-learned, concrete examples):
- `n8n-orchestration-patterns` — fan-out/fan-in, parallel sub-workflows (branch-split trap,
  `executionOrder: v0`, DataTable fan-in), synchronous batch + fast-return webhook.
- `n8n-structured-extraction` — LLM extraction/classification via a real JSON schema (Information
  Extractor / Text Classifier), never Agent+prompt.
- `/n8n-autopilot:data-tables` — now also documents the upsert node shape (3-part requirement) +
  usage patterns (fan-in store, idempotency/dedup, error rows).
