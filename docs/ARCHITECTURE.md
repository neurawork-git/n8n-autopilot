# Architektur: n8n-autopilot Plugin

*Stand: Mai 2026 — Plugin v3.6.1, n8nac ≥ 2.2.0.*

## Grundprinzip

Workflows sind **TypeScript Decorator-Format** (`.workflow.ts`). `n8nac` synchronisiert bidirektional zwischen lokalen Dateien und n8n. Kein SDK, kein Compiler, kein manuelles JSON. Kein Wrapper-Layer — Claude schreibt Decorator-TS direkt; das Wissen WIE steckt im Plugin (Skills, Agents, Hooks).

## Zwei Säulen

```
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│   n8nac (CLI + MCP)              n8n-autopilot Plugin                │
│   ══════════════════              ══════════════════                  │
│   Knowledge (offline):            Skills:                            │
│     - search_n8n_knowledge          - build-workflow (3-Phase)       │
│     - get_n8n_node_info             - deploy                         │
│     - search_n8n_docs               - pull-schemas                   │
│     - search_n8n_workflow_examples  - sync-credentials               │
│     - validate_n8n_workflow         - init-repo                      │
│   (537+ Core, 547+ Community,       - inventory                      │
│    7.7k Templates)                  - check-mcps                     │
│                                     - data-tables (curl carve-out)   │
│   Authoring + Sync (CLI):         Knowledge Skills (model-only):     │
│     - pull / push (--verify)        - n8n-node-configuration         │
│     - list / find                   - n8n-validation-expert          │
│     - validate (--strict --json)    - n8n-workflow-patterns          │
│     - test / test-plan / verify     - n8n-code-javascript            │
│     - resolve / fetch / convert     - n8n-code-python                │
│     - workflow act./deact.          - n8n-expression-syntax          │
│     - credential CRUD                                                │
│     - execution list/get          Agents:                            │
│     - instance / switch             - n8n-researcher  (haiku)        │
│                                     - workflow-reviewer (sonnet)     │
│   Hauptzugang: immer.             Hooks:                             │
│   API-Zugriff via n8n REST          - SessionStart (4 checks)        │
│   bleibt blockiert — außer          - PreToolUse Bash:               │
│   /api/v1/data-tables                 · curl-block (+ DT carve-out)  │
│   (siehe data-tables skill).          · ensure-mcp-trigger setting   │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

## Tool Boundaries

| What | Used | Not used |
|------|------|----------|
| **n8nac MCP** | `search_n8n_knowledge`, `get_n8n_node_info`, `search_n8n_docs`, `search_n8n_workflow_examples`, `validate_n8n_workflow` | — |
| **n8nac CLI** | `push (--verify)`, `pull`, `resolve`, `list`, `find`, `validate (--strict --json)`, `test (--data --query --prod)`, `test-plan`, `verify`, `fetch`, `convert`, `convert-batch`, `workflow activate/deactivate/credential-required/present`, `credential list/get/schema/create/delete`, `execution list/get`, `instance list/add/select/update/delete`, `switch`, `update-ai`, `skills node-info/node-schema/related/guides/list/examples` | — |
| **n8n REST API direct** | Only `/api/v1/data-tables` (curl carve-out, see `data-tables` skill) | Everything else — use n8nac |

## Workflow-Lifecycle (3 Phasen)

```
Phase 0          Phase 1                       Phase 2
┌─────────┐     ┌────────────────────────┐     ┌────────────────────┐
│ Research │────▶│  Write + Validate      │────▶│  Test + Inspect    │
│ n8nac    │     │  .workflow.ts          │     │  n8nac test-plan   │
│ knowledge│     │  + n8nac validate      │     │  n8nac test        │
│          │     │  + n8nac push --verify │     │  n8nac execution   │
└─────────┘     └────────────────────────┘     └────────────────────┘
  offline           needs n8n API                   needs n8n API
```

| Phase | What | Tool |
|-------|------|------|
| **0** | Find nodes, verify params | n8nac MCP `search_n8n_knowledge`, `get_n8n_node_info`; CLI `skills node-info --json` |
| **1** | Write `.workflow.ts` (Decorator-TS) | n8nac CLI `pull` (optional start) + manual editing |
| **1b** | Validate offline | n8nac CLI `skills validate --strict --json` |
| **1c** | Validate against instance | n8nac MCP `validate_n8n_workflow` |
| **1d** | Push + verify remote state | n8nac CLI `push --verify` |
| **2a** | Test (webhook/chat/form) | n8nac CLI `test-plan` → `test` |
| **2b** | Test (schedule/manual/errorTrigger) | Manual: user clicks Execute in n8n UI, reports execution-id |
| **2c** | Inspect outputs | n8nac CLI `execution get --include-data` |
| **2d** | Activate (optional) | n8nac CLI `workflow activate` |
| **2e** | Publish (mcpTrigger only) | Manual: user clicks Publish in n8n UI |

## Datei-Struktur

```
n8n-autopilot/
├── CLAUDE.md                       # Plugin rules, tool boundaries, auto-reactions
├── README.md                       # Public-facing
├── .mcp.json.example               # n8nac MCP-Konfiguration (Vorlage)
│
├── .claude-plugin/
│   ├── plugin.json                 # Plugin manifest
│   └── marketplace.json            # Marketplace entry
│
├── skills/                         # All user + knowledge skills
│   ├── build-workflow/             # /n8n-autopilot:build-workflow
│   ├── deploy/                     # /n8n-autopilot:deploy
│   ├── pull-schemas/               # /n8n-autopilot:pull-schemas
│   ├── sync-credentials/           # /n8n-autopilot:sync-credentials
│   ├── init-repo/                  # /n8n-autopilot:init-repo (+ scripts, assets)
│   ├── inventory/                  # /n8n-autopilot:inventory
│   ├── check-mcps/                 # /n8n-autopilot:check-mcps
│   ├── data-tables/                # /n8n-autopilot:data-tables
│   ├── n8n-node-configuration/     # knowledge
│   ├── n8n-validation-expert/      # knowledge
│   ├── n8n-workflow-patterns/      # knowledge
│   ├── n8n-code-javascript/        # knowledge
│   ├── n8n-code-python/            # knowledge
│   └── n8n-expression-syntax/      # knowledge
│
├── agents/
│   ├── n8n-researcher.md           # haiku — Phase 0 research
│   └── workflow-reviewer.md        # sonnet — pre-deploy review
│
├── hooks/
│   └── hooks.json                  # SessionStart + PreToolUse
│
├── scripts/
│   ├── setup-check.sh              # SessionStart 1: config + reachability
│   ├── check-schema-versions.sh    # SessionStart 2: stale schemas
│   ├── check-credential-freshness.sh  # SessionStart 3: stale credential refs
│   ├── check-installed-nodes.sh    # invoked by setup-check + check-schema-versions
│   ├── check-inventory-freshness.sh   # informational
│   └── ensure-mcp-trigger-setting.sh  # PreToolUse: availableInMCP workflow setting guard
│
├── schemas/nodes/                  # cached node schemas (gitignored)
│
└── docs/
    ├── OVERVIEW.md                 # 1-page summary
    ├── ARCHITECTURE.md             # this document
    ├── MCP.md                      # MCP integration guide
    ├── CREDENTIALS.md              # Credential reference
    ├── COMMUNITY_NODES.md          # Community node registry
    └── INVENTORY.md                # Generated by /inventory
```

## Sync-Modell (n8nac CLI)

```
n8nac list                                    → TRACKED / CONFLICT / LOCAL-ONLY / REMOTE-ONLY / ARCHIVED
                                                # Default hides archived
                                                # --include-archived / --only-archived available
                                                # Archived workflows are read-only — push is rejected
n8nac find <query>                            → Workflow search (shortcut for list --search)
n8nac pull <workflowId>                       → remote JSON → local .workflow.ts
n8nac push workflows/<name>.workflow.ts       → local .workflow.ts → remote n8n
n8nac resolve <id> --mode keep-current        → conflict: local wins
n8nac resolve <id> --mode keep-incoming       → conflict: remote wins
n8nac verify <workflowId>                     → validate remote state against local schema
n8nac test-plan <workflowId> --json           → trigger analysis + payload suggestion
n8nac test <workflowId> --data '{...}'        → hit test URL (no activation needed)
n8nac test <workflowId> --prod                → hit production URL (workflow must be active)
n8nac workflow credential-required <id>       → exit 0 = all credentials present, exit 1 = missing
n8nac fetch <workflowId>                      → explicit remote-state fetch
n8nac convert <file>                          → JSON ↔ TS conversion
n8nac convert-batch <dir>                     → batch conversion of all workflows
n8nac env list/add/update/pin/remove          → environment management (multiple n8n instances)
n8nac env use <name>                          → switch active environment (alias: env pin)
n8nac workspace pin-instance / clear-instance → bind workspace to a specific instance
n8nac update-ai                               → regenerate AGENTS.md + AI context
n8nac skills node-schema <name>               → quick TypeScript snippet for a node
n8nac skills related <query>                  → find related nodes and docs
n8nac skills guides [query]                   → workflow guides and tutorials
```

## MCP-Konfiguration

```json
{
  "mcpServers": {
    "n8n-as-code": { "command": "npx", "args": ["--yes", "n8nac", "mcp"] }
  }
}
```

| Server | Needs n8n? | Purpose |
|--------|-----------|---------|
| **n8n-as-code** | No (offline) | Node discovery, schema validation, template search |

Only this single MCP is used. n8nac is the sole backend for all instance operations. See [CHANGELOG.md](../CHANGELOG.md) (`3.4.0` entry) for the history of the prior multi-MCP architecture.

## Hook-Chain

| Phase | Hook | What it does |
|-------|------|--------------|
| SessionStart | `setup-check.sh` | Verifies Node.js, n8nac min-version (≥ 2.2.0), `.mcp.json`, `n8nac-config.json`, n8n API reachability, community-node schema coverage, inventory freshness |
| SessionStart | `check-schema-versions.sh --quiet` | Compares cached schema `packageVersion` against latest npm — emits `AUTOPILOT_ACTION_REQUIRED: /n8n-autopilot:pull-schemas --packages …` when stale |
| SessionStart | `check-credential-freshness.sh --quiet` | Scans `workflows/**/*.workflow.ts` for credential IDs that do not resolve on the live instance — emits `AUTOPILOT_ACTION_REQUIRED: /n8n-autopilot:sync-credentials` |
| PreToolUse (Bash) | curl-block | Rejects direct `curl`/`wget` against `/api/v1`, `n8n.cloud`, `n8n.io` — **carve-out:** `/api/v1/data-tables` is allowed (for the `data-tables` skill) |
| PreToolUse (Bash) | `ensure-mcp-trigger-setting.sh` | Before `n8nac push`: if workflow contains `mcpTrigger`, auto-fixes the `availableInMCP: false → true` workflow setting and warns if the setting is absent |

Auto-reaction signals (`AUTOPILOT_ACTION_REQUIRED: <slash-command>`) are documented in `CLAUDE.md` — Claude reads the hook output and runs the literal command without asking the user.
