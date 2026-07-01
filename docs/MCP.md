> **Required for Phase 0 + Phase 2.** n8nac skills (Phase 0) work fully offline. n8nac CLI handles push/pull/test/verify/activate/credentials/executions (Phase 1+2) via `npx n8nac`.

# MCP Integration Guide

## Quick Reference

| Task | Server | Phase | Why |
|------|--------|-------|-----|
| **Find a node** | `n8n-as-code` | 0 | `search` — 1,084 nodes, offline, ~5ms |
| **Get node schema** | `n8n-as-code` | 0 | `node-info` — full parameters, docs, examples |
| **Validate workflow** | `n8n-as-code` | 1 | `validate` — catches schema errors before push |
| **Validate (strict/JSON)** | `n8n-as-code` | 1 | `validate --strict` (warnings = errors) · `--json` (machine-readable for agents) |
| **Search templates** | `n8n-as-code` | 0 | `examples search` — 7,702 community workflows |
| **Push workflow** | n8nac CLI (not MCP) | 1 | `npx n8nac push <file>` |
| **Push + auto-verify** | n8nac CLI (not MCP) | 1 | `npx n8nac push <file> --verify` — push and verify in one step |
| **Pull workflow** | n8nac CLI (not MCP) | 1 | `npx n8nac pull <workflowId>` |
| **Sync status** | n8nac CLI (not MCP) | — | `npx n8nac list` — default ohne archivierte; `--include-archived` / `--only-archived` |
| **Resolve conflict** | n8nac CLI (not MCP) | — | `npx n8nac resolve <id> --mode keep-current\|keep-incoming` |
| **Test plan** | n8nac CLI (not MCP) | 2 | `npx n8nac test-plan <id> --json` — trigger analysis + suggested payload |
| **Live test (body/POST)** | n8nac CLI (not MCP) | 2 | `npx n8nac test <id> --data '{...}'` — no activation needed |
| **Live test (query/GET)** | n8nac CLI (not MCP) | 2 | `npx n8nac test <id> --query '{...}'` — for GET/HEAD webhooks reading `$json.query` |
| **Live test (prod URL)** | n8nac CLI (not MCP) | 2 | `npx n8nac test <id> --prod` — workflow must be active |
| **Verify remote state** | n8nac CLI (not MCP) | 1 | `npx n8nac verify <id>` — post-push validation (or use `push --verify`) |
| **Convert JSON↔TS** | n8nac CLI (not MCP) | — | `npx n8nac convert <file>` |
| **Activate workflow** | n8nac CLI (not MCP) | 2 | `npx n8nac workflow activate <id>` |
| **Deactivate workflow** | n8nac CLI (not MCP) | 2 | `npx n8nac workflow deactivate <id>` |
| **List executions** | n8nac CLI (not MCP) | — | `npx n8nac execution list --workflow-id <id>` |
| **List executions (paged)** | n8nac CLI (not MCP) | — | `npx n8nac execution list --cursor <cursor> --limit <n>` |
| **List executions (project)** | n8nac CLI (not MCP) | — | `npx n8nac execution list --project-id <id>` |
| **Get execution details** | n8nac CLI (not MCP) | — | `npx n8nac execution get <executionId> --include-data --json` |
| **List credentials** | n8nac CLI (not MCP) | — | `npx n8nac credential list` |
| **Credential schema** | n8nac CLI (not MCP) | — | `npx n8nac credential schema <type>` — required fields + types |
| **Get credential** | n8nac CLI (not MCP) | — | `npx n8nac credential get <id>` |
| **Delete credential** | n8nac CLI (not MCP) | — | `npx n8nac credential delete <id>` |
| **Check credential presence** | n8nac CLI (not MCP) | 2 | `npx n8nac workflow credential-required <id>` — exit 0/1 |
| **Fetch remote state** | n8nac CLI (not MCP) | — | `npx n8nac fetch <workflowId>` |
| **Switch environment** | n8nac CLI (not MCP) | — | `npx n8nac env list/add/update/pin/remove` + `env use <name>` |
| **Update AI context** | n8nac CLI (not MCP) | — | `npx n8nac update-ai` |
| **Custom MCP tools** | `n8n-custom-tools` | — | MCP Server Trigger workflows (komplementär) |

---

## 1. n8n-as-code — Node Discovery & Validation (PRIMARY)

Offline AI skills layer with embedded n8n ontology. No n8n connection required.

**Package:** `n8nac` (via npx)
**Source:** [github.com/EtienneLescot/n8n-as-code](https://github.com/EtienneLescot/n8n-as-code)

### Coverage

- **1,084 nodes:** 537 core + 547 community
- **10,209 properties** with 17,155 option values
- **7,702 community templates** (FlexSearch, ~5ms queries)
- **1,243 documentation pages** (93% node coverage)
- **170 code examples** from official docs

### Tools (CLI + MCP)

| Command | Purpose |
|---------|---------|
| `npx n8nac skills search <query>` | Find nodes by name/description |
| `npx n8nac skills node-info <name>` | Full schema + docs + examples |
| `npx n8nac skills node-schema <name>` | Quick TypeScript snippet |
| `npx n8nac skills docs [title]` | Access n8n documentation |
| `npx n8nac skills guides [query]` | Tutorials and walkthroughs |
| `npx n8nac skills examples search <query>` | Search community templates |
| `npx n8nac skills validate <file>` | Validate workflow JSON/TypeScript |
| `npx n8nac skills related <query>` | Find related nodes and docs |

### Configuration

**Claude Code (`.mcp.json`):**
```json
{
  "mcpServers": {
    "n8n-as-code": {
      "command": "npx",
      "args": ["--yes", "n8nac", "mcp"]
    }
  }
}
```

All tools also work as CLI commands — no MCP server required.

### n8nac CLI sync (push/pull/resolve) — PRIMARY deploy method

n8nac has a git-like sync engine with push/pull/resolve commands. **This is our primary deploy method.**

```bash
npx n8nac init                                    # one-time: connect to n8n instance
npx n8nac list                                    # show sync status
npx n8nac pull <workflowId>                       # download workflow as .workflow.ts
npx n8nac push workflows/<name>.workflow.ts       # upload to n8n
npx n8nac resolve <id> --mode keep-current        # conflict: use local
npx n8nac resolve <id> --mode keep-incoming       # conflict: use remote
```

**Sync states:**
- `TRACKED` — local and remote in sync
- `CONFLICT` — both sides changed, needs resolve
- `LOCAL-ONLY` — not yet pushed
- `REMOTE-ONLY` — not yet pulled

Skills (search, node-info, validate, examples) work fully offline without initialization.

### n8nac CLI — Testing & Verification (v1.2+)

These commands require `n8nac init` (n8n API connection). They are the **primary method for testing workflows**.

```bash
# Test planning — check if workflow is testable + get suggested payload
npx n8nac test-plan <workflowId> --json
# Returns: { triggerType, testable, suggestedPayload, testUrl }

# Live test via test URL (no activation needed)
npx n8nac test <workflowId> --data '<json-payload>'
# Exit 0 = success or Class A error (missing credentials — inform user)
# Exit 1 = Class B error (wiring bug — agent should fix and re-test)

# Production URL test (workflow must be active)
npx n8nac test <workflowId> --prod --data '<json-payload>'

# Verify remote state matches local schema (post-push check)
npx n8nac verify <workflowId>
```

**Error classification:**
| Exit Code | Class | Meaning | Agent Action |
|-----------|-------|---------|-------------|
| 0 | Success | Workflow executed correctly | Done |
| 0 | Class A | Config gap (missing credentials/model) | Inform user, do not block |
| 1 | Class B | Wiring error (bad expressions, wrong fields) | Fix → re-validate → re-push → re-test |
| 1 | Fatal | Infrastructure error (no trigger, workflow not found) | Report to user |

### n8nac CLI — Activate, Credentials & Executions (v1.3+)

```bash
# Workflow Lifecycle
npx n8nac workflow activate <workflowId>         # activate for production
npx n8nac workflow deactivate <workflowId>       # deactivate
npx n8nac workflow credential-required <id>      # exit 0 = all present, exit 1 = missing

# Credential Management
npx n8nac credential list                        # all credentials
npx n8nac credential get <id>                    # details
npx n8nac credential schema <type>               # credential type schema
npx n8nac credential create --type slack --name "My Slack"  # create new
npx n8nac credential delete <id>                 # delete credential

# Execution Debugging
npx n8nac execution list --workflow-id <id> --status error   # failed executions
npx n8nac execution get <executionId> --include-data      # full execution data
```

### n8nac CLI — Environment-Management (v2.x)

```bash
npx n8nac env list                               # alle konfigurierten Environments
npx n8nac env add <name> --base-url <url> --workflows-path workflows  # neues Environment hinzufügen + binden
printf '%s' "$N8N_API_KEY" | npx n8nac env auth set <name> --api-key-stdin  # API-Key für Environment setzen
npx n8nac env use <name>                         # aktives Environment wechseln (alias: env pin)
npx n8nac env update <name> --project-name <p>  # Environment-Felder ändern (z. B. Projekt setzen)
npx n8nac env remove <name>                      # Environment entfernen
npx n8nac env status                             # aktuell aktives Environment anzeigen
npx n8nac fetch <workflowId>                     # Remote-State explizit abrufen
```

Nützlich für Teams, die zwischen dev/staging/prod-Environments wechseln. Ab n8nac 2.3.0 ist `workspace` vollständig read-only (`workspace status` / `workspace get` bleiben erhalten). Alle Mutations (Instanz-Binding, Projekt, Sync-Ordner) erfolgen ausschließlich über `env add` / `env update`. Die früheren Befehle `workspace pin-instance`, `workspace set-project`, `workspace set-sync-folder` sowie `instance-target` sind entfernt.

### n8nac CLI — AI-Kontext (v1.5+)

```bash
npx n8nac update-ai                              # AGENTS.md + Snippets regenerieren
npx n8nac init-ai                                # initiale AI-Kontext-Dateien erstellen
```

`update-ai` regeneriert `AGENTS.md` und Prompt-Snippets aus dem aktuellen n8nac-Wissen — sinnvoll nach Major-Updates oder neuen Credential-Konfigurationen.

### n8nac CLI — Conversion & Search

```bash
# Convert between JSON and TypeScript formats
npx n8nac convert <file> -o <output>
npx n8nac convert-batch <directory>

# Search workflows by name
npx n8nac find <query>

# Download community template as TypeScript
npx n8nac skills examples download <templateId>
```

---

## 2. MCP Server Trigger — Custom Tools (komplementär)

Expose n8n workflows as custom MCP tools via the MCP Server Trigger node (`@n8n/n8n-nodes-langchain.mcpTrigger`). The endpoint becomes reachable once the workflow is **published** in the n8n UI.

> **Manuelles Publish nötig:** n8nac kann Drafts nicht publishen. Nach `npx n8nac push` eines mcpTrigger-Workflows zeigt der `deploy` skill einen prominenten UI-Klick-Hinweis. Ohne Publish liefert der MCP-Endpoint 404.

### Configuration

```json
{
  "mcpServers": {
    "n8n-custom-tools": {
      "command": "npx",
      "args": ["-y", "mcp-remote",
               "https://<domain>/mcp/<workflow-path>",
               "--header", "Authorization: Bearer <TOKEN>"]
    }
  }
}
```

Create an MCP Server Trigger workflow in n8n to expose custom tools. Publish manually after each `npx n8nac push`.

---

## Alternative: n8n-mcp (czlonkowski) — nicht Teil dieses Plugins

Ein separater Third-Party MCP Server mit größerer Node-Coverage und zusätzlichen Real-World-Configs.

**Warum nicht im Plugin:** Kein Decorator-TS Support, starker Overlap mit n8nac (Discovery + Schema-Validation), zusätzlicher MCP-Server = unnötige Komplexität, Pflege-Last verdoppelt.

**Für wen interessant:** Nutzer ohne Decorator-TS-Workflow, die auf maximale Node-Coverage und reine JSON-Konfigurationen optimieren. Installation: `npx n8n-mcp` als stdio-Server.

---

## Token Types

| Token | Usage |
|-------|-------|
| `PUBLIC_API_KEY` | n8nac sync (all workflow management & execution) |
| `MCP_BEARER_TOKEN` | MCP Server Trigger workflows (custom tools) |

**API Key generieren:** Settings → n8n API → Create API Key

---

## Troubleshooting

**n8nac skills not returning results:**
```bash
# Test directly
npx --yes n8nac skills search "slack"
# Check Node.js version (requires 18+)
node --version
```

**MCP Server Trigger workflow returns 404:**
- Workflow must be **published** in the n8n UI (n8nac cannot publish drafts — click "Publish" after each push)
- Use production URL (not test)
- Check bearer token is correct

---

## Links

- [n8n-as-code GitHub](https://github.com/EtienneLescot/n8n-as-code)
- [n8n MCP Server Docs](https://docs.n8n.io/advanced-ai/accessing-n8n-mcp-server/)
- [MCP Server Trigger Docs](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-langchain.mcptrigger/)

