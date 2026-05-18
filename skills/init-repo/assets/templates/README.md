# {{REPO_NAME}}

n8n workflows for {{REPO_NAME}}, built with the [n8n-autopilot](https://github.com/nashtrader/n8n-autopilot) Claude Code plugin.

## Quick Start

```bash
# 1. Install dependencies (plugin pulls n8nac via npx — no global install required)
npm install   # optional, only if you add deps later

# 2. Configure n8n connection
cp .env.example .env          # fill in N8N_API_URL + N8N_API_KEY
npx n8nac init                # writes n8nac-config.json (gitignored)

# 3. Cache node schemas for offline validation
# In Claude Code:
#   /n8n-autopilot:pull-schemas

# 4. Verify setup
bash "$(claude plugin path n8n-autopilot)/scripts/setup-check.sh"
```

## Build a Workflow

In Claude Code:

```
/n8n-autopilot:build-workflow "describe what the workflow should do"
```

The plugin handles research (Phase 0), scaffolding, validation, deploy, and test.

## Deploy

```
/n8n-autopilot:deploy workflows/my-workflow.workflow.ts
```

Or manually:

```bash
npx n8nac push workflows/my-workflow.workflow.ts --verify
```

## Repo Layout

| Path | Purpose |
|------|---------|
| `workflows/` | TypeScript Decorator workflows (`*.workflow.ts`) |
| `schemas/nodes/` | Cached node schemas (gitignored, populated by `pull-schemas`) |
| `data/` | Local data referenced by workflows |
| `docs/` | Design docs, runbooks |
| `CLAUDE.md` | Claude Code project rules |
| `.env.example` | Required environment variables |

## Plugin Reference

Full command reference + tool boundaries: see `CLAUDE.md` and the plugin docs at
`$(claude plugin path n8n-autopilot)/CLAUDE.md`.
