# Overview — n8nac & n8n-autopilot Plugin

*Einseiter — Stand Mai 2026 (Plugin v3.6.0, n8nac ≥ 2.2.0).*
*Tiefe Details: [ARCHITECTURE.md](ARCHITECTURE.md) · [MCP.md](MCP.md).*

---

## Zwei-Säulen-Architektur — wer macht was

| Säule | Zweck | Braucht n8n? | Wann genutzt |
|---|---|---|---|
| **n8nac** (CLI + MCP) — *PRIMARY* | Node-Wissen + Authoring + Sync + Test + Ops | MCP: nein · CLI: ja | Immer |
| **n8n-autopilot Plugin** — *ORCHESTRATION* | Pipelines (Skills), Agents, Hooks, Validation-Loop | — | Immer |

---

## Was wir mit n8nac machen

**Wissen (offline, ~5 ms):** `search_n8n_knowledge`, `get_n8n_node_info`, `search_n8n_docs`, `search_n8n_workflow_examples` (537 core + 547 community Nodes, 7.7k Templates).

**Exakte TypeScript-Defs:** `npx n8nac skills node-info <name> --json` / `skills node-schema --json` — liest aus `schemas/nodes/` (regelmäßig per `/n8n-autopilot:pull-schemas` aktualisiert, Drift-Warnung beim SessionStart).

**Authoring & Sync (CLI):**
- `pull <id>` / `push <file>` / `push --verify` / `verify <id>` / `resolve <id>` / `fetch <id>`
- `list` (default ohne archivierte; `--include-archived` / `--only-archived`) · `find <q>`
- `convert` / `convert-batch` (JSON ↔ Decorator-TS)

**Testing:** `test-plan <id> --json` · `test <id> --data|--query|--prod` · Exit-Code-Klassifizierung (Class A = User informieren, Class B = Fix-Loop).

**Operations:** `workflow activate|deactivate|credential-required` · `credential list|get|schema|create|delete` · `execution list|get --include-data` · `instance list|add|select|update|delete` · `update-ai`.

**Validation (offline):** `skills validate [--strict] [--json]` — strukturierter Output für Agent-Pipelines.

**Format:** Workflows sind **Decorator-TS** (`@workflow({...})`) — kein SDK, kein Compiler, kein Build-Step. Niemals JSON von Hand schreiben.

---

## Was das n8n-autopilot Plugin oben drauf legt

**Pipelines (User-Skills):**
- `/n8n-autopilot:init-repo [target]` — Repo-Bootstrap (Layout + CLAUDE.md + n8nac init + Schema-Pull)
- `/n8n-autopilot:build-workflow "<beschreibung>"` — End-to-End: Phase 0 (Research) → Phase 1 (Write + Validate + Push) → Phase 2 (Test)
- `/n8n-autopilot:deploy <file>` — Push + Verify, Hinweis bei `mcpTrigger` für manuelles Publish
- `/n8n-autopilot:pull-schemas` — Community-Node-Schemas auffrischen (`--packages` für gezielten Refresh)
- `/n8n-autopilot:sync-credentials` — Credential-IDs aus Live-Instanz listen
- `/n8n-autopilot:inventory` — `docs/INVENTORY.md` aus lokalen Workflows aggregieren
- `/n8n-autopilot:check-mcps` — Check der n8nac MCP-Verbindung
- `/n8n-autopilot:data-tables` — DataTable-Lifecycle via REST-API (curl Carve-out)

**Knowledge-Skills (model-only):** `n8n-node-configuration`, `n8n-validation-expert`, `n8n-workflow-patterns`, `n8n-code-javascript`, `n8n-code-python`, `n8n-expression-syntax`.

**Agents:** `n8n-researcher` (Haiku, Phase-0-Recherche) · `workflow-reviewer` (Sonnet, Code-Review vor Push).

**Hooks (im Harness erzwungen):**
- *SessionStart 1:* `setup-check.sh` — Config + Reachability + n8nac min-version + Community-Node-Coverage + Inventory-Freshness
- *SessionStart 2:* `check-schema-versions.sh --quiet` — stale Community-Node-Schemas → `AUTOPILOT_ACTION_REQUIRED: /n8n-autopilot:pull-schemas --packages …`
- *SessionStart 3:* `check-credential-freshness.sh --quiet` — Workflow referenziert nicht existierende Credential-ID → `AUTOPILOT_ACTION_REQUIRED: /n8n-autopilot:sync-credentials`
- *PreToolUse (Bash):* blockt direkten REST-API-Zugriff (curl/wget gegen `/api/v1`, `n8n.cloud`, `n8n.io`) — **Carve-out:** `/api/v1/data-tables` ist erlaubt. Plus `ensure-mcp-trigger-setting.sh` (auto-guard `availableInMCP` Workflow-Setting für `mcpTrigger`-Pushes)
- *Auto-Reactions:* Claude führt `AUTOPILOT_ACTION_REQUIRED:`-Zeilen wörtlich ohne Rückfrage aus (CLAUDE.md Mapping)

**Manuelle Schritte (n8nac-Limits):**
- **mcpTrigger-Workflows:** Nach jedem Push muss in der n8n-UI „Publish" geklickt werden — sonst 404 am MCP-Endpoint. Der `deploy` skill und `build-workflow` Path D zeigen einen prominenten Hinweis.
- **Schedule/Manual/ErrorTrigger:** `n8nac test` kann diese nicht auslösen — User klickt "Execute Workflow" in der n8n-UI, meldet die `execution-id` an Claude, Claude inspiziert via `npx n8nac execution get --include-data`.

**Konventionen (in CLAUDE.md kodifiziert):**
- Niemals direkt n8n REST API aufrufen (curl/fetch/HTTP Request) → n8nac CLI — **Ausnahme:** `/api/v1/data-tables` via `data-tables` skill
- Niemals Workflow-JSON von Hand schreiben → Decorator-TS Format
- Niemals Workflows ohne explizite User-Bestätigung löschen
- Niemals `continueOnFail: true` ohne explizite User-Anweisung — maskiert Silent Failures
- Niemals HTTP/fetch/axios in Code-Nodes — HTTPRequest-Node verwenden
- Archivierte Workflows sind read-only — Push wird abgelehnt

---

## Schnell-Entscheidungsbaum

| Frage | Tool |
|---|---|
| Welcher Node hat welche Parameter? | n8nac `search_n8n_knowledge` → `get_n8n_node_info` |
| Exakte TypeScript-Defs? | `npx n8nac skills node-info <name> --json` |
| Validieren vor Push? | n8nac `skills validate --strict --json` |
| Push + sofortige Remote-Validierung? | n8nac CLI `push --verify` |
| Webhook-Workflow live testen? | n8nac CLI `test --data` / `--query` / `--prod` |
| Schedule-/Manual-/ErrorTrigger testen? | n8n-UI „Execute Workflow" + `n8nac execution get` |
| Execution-Output debuggen? | `npx n8nac execution get <id> --include-data` |
| MCP-Trigger-Workflow live halten? | n8n-UI „Publish" nach jedem Push |
| End-to-End neu bauen? | `/n8n-autopilot:build-workflow "<text>"` |

---

## Token-Modell

| Token | Wofür | Wo generieren |
|---|---|---|
| `PUBLIC_API_KEY` | n8nac sync (Workflow-Management + Execution) | n8n UI → Settings → n8n API |
| `MCP_BEARER_TOKEN` | Custom MCP Server Trigger Workflows (legacy) | im Workflow definiert |
