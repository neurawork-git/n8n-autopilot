<div align="center">

# 🤖 n8n-autopilot

**A Claude Code plugin that turns natural-language prompts into validated, deployed n8n workflows.**

[![Version](https://img.shields.io/badge/version-3.6.0-blue.svg)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Node.js](https://img.shields.io/badge/node-%E2%89%A518-339933.svg?logo=node.js&logoColor=white)](https://nodejs.org)
[![n8nac](https://img.shields.io/badge/n8nac-%E2%89%A52.2.0-ff6d5a.svg)](https://www.npmjs.com/package/n8nac)
[![Claude Code](https://img.shields.io/badge/claude%20code-plugin-d97757.svg)](https://docs.claude.com/claude-code)

```
/n8n-autopilot:build-workflow "Webhook receives Stripe payment → updates Postgres → sends Slack alert"
```

</div>

Claude researches the exact node parameters, writes validated TypeScript, pushes to your n8n instance, and live-tests — without you touching the n8n UI.

---

## Table of Contents

- [Why This Exists](#why-this-exists)
- [What You Can Do](#what-you-can-do)
- [How the Build Pipeline Works](#how-the-build-pipeline-works)
- [Skills Reference](#skills-reference)
- [Setup](#setup)
- [Workflow Format](#workflow-format)
- [Sync: Local ↔ n8n](#sync-local--n8n)
- [Plugin Structure](#plugin-structure)
- [Documentation](#documentation)
- [Changelog](CHANGELOG.md)

---

## Why This Exists

Building n8n workflows manually means:
- Looking up node parameter names in docs
- Guessing credential key formats
- Pushing broken JSON and debugging at runtime

This plugin gives Claude Code deep n8n expertise — 537+ node schemas, 7,700 community templates, expression validation, live testing — so it can build production-quality workflows correctly the first time.

---

## What You Can Do

### Build workflows from a description

```
/n8n-autopilot:build-workflow "Every morning at 8am, fetch open GitHub issues, filter by label 'urgent', post summary to Slack"
```

```
/n8n-autopilot:build-workflow "HTTP webhook receives customer data, validates email, upserts to Postgres, returns confirmation"
```

```
/n8n-autopilot:build-workflow "RSS feed monitor: check every hour, detect new items, summarize with GPT-4o-mini, send digest email"
```

Claude runs a 3-phase pipeline automatically:
1. **Research** — discovers exact node types and parameters via n8nac (offline, ~5ms per node)
2. **Write + Validate** — writes Decorator-TS, validates against 537+ schemas, pushes to n8n
3. **Deploy + Test** — tests via test URL (no activation needed), classifies errors, fixes and retries

### Bootstrap a new repo in one command

```
/n8n-autopilot:init-repo my-customer
```

Scaffolds the directory layout, writes a plugin-compatible `CLAUDE.md`, runs `npx n8nac init`, pulls node schemas, and verifies — so the first `build-workflow` call works immediately.

### Deploy an existing workflow file

```
/n8n-autopilot:deploy workflows/my-workflow.workflow.ts
```

### Discover or repair credential IDs

```
/n8n-autopilot:sync-credentials                    # list live credentials
/n8n-autopilot:sync-credentials --fix-workflows    # rewrite stale IDs in workflows/, matched by credential name
```

`--fix-workflows` is what the SessionStart credential-freshness hook auto-triggers when it detects stale references.

### Inventory your workflows

```
/n8n-autopilot:inventory
```

Aggregates every node type, LLM model, credential, and trigger used across `workflows/**/*.workflow.ts` into `docs/INVENTORY.md`. Useful when planning a new workflow, onboarding to an existing project, or auditing consistency across an instance.

### Manage DataTable resources

```
/n8n-autopilot:data-tables
```

n8nac has no DataTable subcommand. This skill documents every `/api/v1/data-tables` endpoint (tables, columns, rows) with copy-paste curl recipes — the only Claude-accessible REST API path past the PreToolUse curl-block.

### Check MCP health

```
/n8n-autopilot:check-mcps
```

Two-layer check: infrastructure reachability (endpoints, tokens) AND tool registration in the active Claude context. Use after setup or when MCP tools seem unavailable.

### Ask for help with n8n specifics

```
How do I access webhook data in a Code node?
```
```
What's the correct expression syntax to reference data from a previous node?
```
```
Why is my IF node operator validation failing?
```

The plugin's guidance skills activate automatically — JavaScript/Python Code nodes, expression syntax, validation errors, workflow patterns.

---

## How the Build Pipeline Works

```
Phase 0                   Phase 1                         Phase 2
Research                  Write + Validate + Push         Deploy + Test
────────────────────────  ──────────────────────────────  ────────────────────────
n8n-researcher (Haiku)    Claude writes .workflow.ts      npx n8nac test-plan
                          workflow-reviewer (Sonnet)      npx n8nac test [--query]
search_n8n_knowledge()    npx n8nac skills validate       ← exit 0 = Class A (inform)
                            --strict --json               ← exit 1 = Class B (fix)
get_n8n_node_info()       fix → re-validate loop
search_n8n_workflow_      npx n8nac push --verify         npx n8nac workflow activate
  examples()              ← push + remote check in 1 →   npx n8nac execution get

No n8n API needed         Decorator-TS format,            n8n API required
                          never hand-written JSON

```

**Error classification after live test:**

| Exit | Class | Meaning | What happens |
|------|-------|---------|-------------|
| 0 | Success | Workflow ran correctly | Done |
| 0 | Class A | Missing credentials/model | Reported to user, not blocked |
| 1 | Class B | Wiring error (bad expression, wrong field) | Claude fixes → re-validates → re-pushes → re-tests |
| 1 | Fatal | No trigger, workflow not found | Reported to user |

**MCP Trigger workflows:** Workflows containing `@n8n/n8n-nodes-langchain.mcpTrigger` expose an MCP endpoint that is only reachable in the *published* version. n8nac cannot publish drafts — after every push, the deploy pipeline shows a prominent notice prompting the user to click "Publish" in the n8n UI.

**Non-HTTP triggers (schedule, manual, errorTrigger):** n8nac cannot trigger these. The `build-workflow` pipeline (Path B) stops after push and prompts the user to click "Execute Workflow" in the n8n UI; once an execution-id is reported back, Claude inspects results via `npx n8nac execution get --include-data`.

---

## Skills Reference

### Slash Commands

| Command | What it does |
|---------|-------------|
| `/n8n-autopilot:init-repo [target]` | Scaffold a brand-new n8n workflow repo: directory layout, CLAUDE.md, n8nac config, schemas — in one step |
| `/n8n-autopilot:build-workflow "description"` | Full pipeline: research → write → validate → push → live-test |
| `/n8n-autopilot:deploy <path>` | Push + optionally activate an existing `.workflow.ts` |
| `/n8n-autopilot:pull-schemas [--packages …]` | Update node schemas for offline validation (targeted refresh via `--packages`) |
| `/n8n-autopilot:sync-credentials [--fix-workflows]` | Discover credential IDs from the live instance; with `--fix-workflows` rewrites stale IDs in local files |
| `/n8n-autopilot:inventory` | Aggregate node-type / LLM / credential usage from local workflows into `docs/INVENTORY.md` |
| `/n8n-autopilot:data-tables` | Manage DataTable resources (tables, columns, rows) via the n8n REST API (curl carve-out) |
| `/n8n-autopilot:check-mcps` | Check the n8nac MCP connection (infrastructure + tool registration) |

### Guidance Skills (auto-activated, also directly invocable)

**Workflow building:**

| Skill | Covers |
|-------|--------|
| `n8n-workflow-patterns` | 5 patterns: webhook processing, HTTP API, database ops, AI agent, scheduled tasks |
| `n8n-node-configuration` | Operation-aware config, property dependencies, required fields by node type |
| `n8n-validation-expert` | Error types, false positives, expression validation, auto-sanitization, bulk fixes |

**Code nodes:**

| Skill | Covers |
|-------|--------|
| `n8n-code-javascript` | `$input`/`$json`/`$node`, `$helpers.httpRequest()`, DateTime (Luxon), return format, top 5 mistakes |
| `n8n-code-python` | `_input`/`_json`, standard library only (no requests/pandas), workarounds |
| `n8n-expression-syntax` | `={{ }}` format, webhook `.body` structure, `$node["Name"]` references, common mistakes |

---

## Setup

### Prerequisites

- **Node.js 18+**
- **n8nac ≥ 2.2.0** (auto-installed via `npx`; the plugin enforces the minimum)
- **Claude Code**
- **Running n8n instance** — local (`docker run -p 5678:5678 n8nio/n8n`) or [n8n Cloud](https://app.n8n.cloud)
- **n8n API key** — n8n UI → Settings → n8n API → Create API Key

### 1. Install the plugin

```bash
claude plugin marketplace add nashtrader/n8n-autopilot
claude plugin install n8n-autopilot@n8n-autopilot
```

**For teams:** commit this to `.claude/settings.json` — teammates get the plugin automatically:

```json
{
  "extraKnownMarketplaces": {
    "n8n-autopilot": {
      "source": { "source": "github", "repo": "nashtrader/n8n-autopilot" }
    }
  },
  "enabledPlugins": {
    "n8n-autopilot@n8n-autopilot": true
  }
}
```

### 2. Configure MCP servers

```bash
cp "$(claude plugin path n8n-autopilot)/.mcp.json.example" .mcp.json
```

The `.mcp.json` is pre-configured and works out of the box — n8nac reads its config from `n8nac-config.json`:

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

### 3. Initialize n8nac sync

```bash
npx n8nac init
```

`init` prompts for the host URL, API key, and project, then writes `n8nac-config.json` (gitignored). For non-interactive setup (CI / agents):

```bash
npx n8nac init-auth --yes && npx n8nac init-project --yes
```

### 4. Pull node schemas

```
/n8n-autopilot:pull-schemas
```

Schemas are not committed — they are instance-specific (community nodes vary per user). This step populates `schemas/nodes/` with the core nodes plus whichever community nodes your n8n instance has installed. Re-run whenever you install a new community node or see stale-schema warnings at session start.

### 5. Verify everything works

```bash
bash scripts/setup-check.sh
```

Checks Node.js version, n8nac min-version (≥ 2.2.0), config, MCP entries, API credentials, live connectivity, and stale community node schemas. Fix any errors before building workflows.

---

## Workflow Format

Workflows are **Decorator-TS** (`.workflow.ts`) — not raw JSON. Claude writes this; you never edit it manually.

```typescript
@workflow({ name: "Stripe → Postgres → Slack", settings: { errorWorkflow: "" } })
class StripePaymentWorkflow {

  @trigger({ type: "n8n-nodes-base.webhook", parameters: { path: "stripe-payment", httpMethod: "POST" } })
  Webhook = {};

  @node({ type: "n8n-nodes-base.postgres", typeVersion: 2.5, parameters: {
    operation: "upsert", schema: { __rl: true, value: "public", mode: "list" },
    table: { __rl: true, value: "payments", mode: "list" },
  }})
  UpdateDatabase = {};

  @node({ type: "n8n-nodes-base.slack", typeVersion: 2.2, parameters: {
    authentication: "oAuth2", resource: "message", operation: "post",
    select: "channel", channelId: { __rl: true, mode: "id", value: "#payments" },
    text: "={{ $json.body.amount }} received from {{ $json.body.customer }}",
  }})
  SendAlert = {};

  @links()
  flow() { return this.Webhook.out().to(this.UpdateDatabase).to(this.SendAlert); }
}
```

---

## Sync: Local ↔ n8n

```bash
npx n8nac list                                         # show sync status: TRACKED / CONFLICT / LOCAL-ONLY / REMOTE-ONLY (excludes archived)
npx n8nac list --include-archived --json               # include archived; structured output for agents
npx n8nac list --search <q> --sort name --limit 20     # filter, sort, paginate; --local / --remote scope
npx n8nac find <query>                                 # quick fuzzy search across workflows
npx n8nac pull <workflowId>                            # download from n8n as .workflow.ts
npx n8nac push workflows/<name>.workflow.ts            # upload to n8n
npx n8nac push workflows/<name>.workflow.ts --verify   # upload + validate remote state in one step
npx n8nac resolve <id> --mode keep-current             # conflict: use local version
npx n8nac resolve <id> --mode keep-incoming            # conflict: use n8n version

npx n8nac test <workflowId> --data '{"key":"value"}'   # live test via test URL (POST/body)
npx n8nac test <workflowId> --query '{"key":"value"}'  # live test via test URL (GET/query params)
npx n8nac test <workflowId> --prod                     # test via production URL (workflow must be active)

npx n8nac workflow credential-required <id>            # check if all credentials are present (exit 0 = ok, exit 1 = missing)
npx n8nac workflow activate <id>                       # activate workflow for production
npx n8nac workflow deactivate <id>                     # deactivate workflow

npx n8nac execution list --workflow-id <id>            # list executions for a workflow
npx n8nac execution list --status error --json         # filter by status, machine-readable output
npx n8nac execution get <execId> --include-data        # full execution data for debugging

npx n8nac credential list                              # list all credentials
npx n8nac credential schema <type>                     # show required fields for a credential type

npx n8nac fetch <workflowId>                           # explicitly fetch remote state
npx n8nac update-ai                                    # regenerate AGENTS.md + AI context

npx n8nac skills validate <file> --strict --json       # local validation (structured output for agents)
npx n8nac skills node-schema <name> --json             # quick TypeScript snippet for a node
npx n8nac skills node-info <name> --json               # full node info
npx n8nac skills examples search/list/info/download    # browse + download community templates
npx n8nac skills list --nodes --docs --guides          # enumerate available references

npx n8nac env list/add/update/pin/remove               # manage workspace environments (multiple n8n instances)
npx n8nac env use <name>                               # switch active environment (alias: env pin)
npx n8nac workspace pin-instance / clear-instance      # bind workspace to a specific instance
```

---

## Plugin Structure

```
n8n-autopilot/
├── .claude-plugin/
│   ├── plugin.json                  Plugin manifest (v3.6.0)
│   └── marketplace.json             Marketplace entry
│
├── skills/
│   ├── init-repo/                   /n8n-autopilot:init-repo  (+ scripts/, assets/)
│   ├── build-workflow/              /n8n-autopilot:build-workflow
│   ├── deploy/                      /n8n-autopilot:deploy
│   ├── pull-schemas/                /n8n-autopilot:pull-schemas
│   ├── sync-credentials/            /n8n-autopilot:sync-credentials
│   ├── inventory/                   /n8n-autopilot:inventory
│   ├── data-tables/                 /n8n-autopilot:data-tables
│   ├── check-mcps/                  /n8n-autopilot:check-mcps
│   ├── n8n-node-configuration/      Knowledge: node config + property dependencies (+ references/)
│   ├── n8n-validation-expert/       Knowledge: validation errors + expression validation (+ references/)
│   ├── n8n-workflow-patterns/       Knowledge: 5 architectural patterns (+ references/)
│   ├── n8n-code-javascript/         Knowledge: JS Code node reference
│   ├── n8n-code-python/             Knowledge: Python Code node reference
│   └── n8n-expression-syntax/       Knowledge: expression syntax + common mistakes
│
├── agents/
│   ├── n8n-researcher.md            Phase 0: node discovery (Haiku)
│   └── workflow-reviewer.md         Phase 1: pre-deploy code review (Sonnet)
│
├── hooks/hooks.json                 SessionStart: setup-check + schema-version + credential-freshness
│                                    PreToolUse: block direct REST API (carve-out for /api/v1/data-tables)
│                                                + auto-guard `availableInMCP` workflow setting
│
├── scripts/
│   ├── setup-check.sh               SessionStart 1: config + reachability + community-node coverage + inventory freshness
│   ├── check-schema-versions.sh     SessionStart 2: stale community-node schemas
│   ├── check-credential-freshness.sh   SessionStart 3: stale credential refs in workflows
│   ├── check-installed-nodes.sh     Indirect: installed nodes missing from schema cache
│   ├── check-inventory-freshness.sh    Indirect: INVENTORY.md staleness (informational)
│   └── ensure-mcp-trigger-setting.sh   PreToolUse on `n8nac push`: guards `availableInMCP`
│
├── .mcp.json.example                MCP server config template (copy to .mcp.json)
├── schemas/nodes/                   Cached node schemas (gitignored, populated by /pull-schemas)
├── docs/                            Architecture, MCP guide, credentials, community-node registry, inventory
└── CHANGELOG.md                     Release history
```

---

## Documentation

| Document | Content |
|----------|---------|
| [docs/OVERVIEW.md](docs/OVERVIEW.md) | One-pager: how we use n8nac and what this plugin adds |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design, workflow lifecycle, sync model |
| [docs/CREDENTIALS.md](docs/CREDENTIALS.md) | Credential types, IDs, usage in Decorator-TS |
| [docs/COMMUNITY_NODES.md](docs/COMMUNITY_NODES.md) | 15 verified community nodes with schemas |
