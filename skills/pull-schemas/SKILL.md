---
name: pull-schemas
description: Pull/update n8n node schemas for offline validation. Discovers node types from local workflows, fetches each via `npx n8nac skills node-info`, falls back to direct npm-package extraction for nodes n8nac does not index, then rebuilds `schemas/_index.json`. Run when schemas are stale, when validation reports "unknown node type", or when SessionStart hooks signal coverage gaps.
argument-hint: "[--core-only] [--community-only] [--nodes node1,node2] [--packages pkg1,pkg2]"
user-invocable: true
allowed-tools: Bash(bash:*), Bash(node:*), Bash(npm:*), Bash(npx:*)
---

# Pull Node Schemas

All work happens in `scripts/run.sh` (colocated in this skill). The skill body is short on purpose — read the script's `--help` for the full flag reference.

## How to invoke

Always call the bundled orchestrator. Do not write ad-hoc loops or improvise around the CLI calls.

```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/pull-schemas/scripts/run.sh" [flags]
```

| Flag | Meaning |
|------|---------|
| (none) | Discover all node types referenced in `workflows/**/*.workflow.ts`, fetch all, rebuild index |
| `--core-only` | Skip community nodes (only `n8n-nodes-base.*`) |
| `--community-only` | Skip core nodes |
| `--nodes <list>` | Skip discovery, fetch this comma-separated list of node types |
| `--packages <list>` | Skip Stage 1 entirely, jump straight to Stage 2 (npm extraction) for each package — what the SessionStart auto-reaction emits |
| `--workspace <dir>` | Workspace root (default: current directory) |
| `--no-index` | Skip the final index rebuild |

The script runs three stages internally:

1. **Stage 1** — for each discovered node type: `npx n8nac skills node-info <type> --json > schemas/nodes/<type>.json`. If n8nac returns "not found", schedule the type's package for Stage 2.
2. **Stage 2** — for any package n8nac did not cover (or any package passed via `--packages`): install it into a temp dir together with `n8n-workflow`, instantiate each exported node class, write the `description` payload to `schemas/nodes/<pkg>.<node>.json` (scoped packages get a per-scope subdir).
3. **Stage 3** — walk `schemas/nodes/**` and rebuild `schemas/_index.json` with `type → {file, displayName, packageVersion}`.

## When to auto-trigger this skill

| Situation | Invocation |
|-----------|------------|
| `npx n8nac skills node-info <type>` returns empty/not-found mid-workflow | `--packages <pkg-prefix>` for that single package |
| n8nac validation reports `unknown node type` | `--packages <pkg-prefix>`, then re-validate |
| `packageVersion: null` in `_index.json` for a community node | `--packages <pkg>` to refresh the versioned schema |
| SessionStart `check-schema-versions.sh` emits `AUTOPILOT_ACTION_REQUIRED: /n8n-autopilot:pull-schemas --community-only --packages <list>` | Run the literal command from the auto-reaction line |

**In `/n8n-autopilot:build-workflow`** — if Phase 0 `skills node-info` returns empty for a community node, invoke `run.sh --packages <pkg>` inline before proceeding. The gate "verified parameter names for every node" requires a valid schema.

## Companion scripts

- `scripts/discover-types.sh` — grep node types out of `workflows/**/*.workflow.ts`
- `scripts/fetch-one.sh` — fetch one indexed node via n8nac CLI (exit 1 = "not in n8nac index, try Stage 2")
- `scripts/fetch-pkg.js` — extract every exported node class from a published npm package
- `scripts/rebuild-index.js` — rebuild `schemas/_index.json`

Each is callable on its own when you need to debug a single step. The skill body intentionally does not duplicate their logic — they are the source of truth.

## Staleness + coverage check

These two diagnostics live as SessionStart hooks (plugin-wide) and can also be run manually:

```bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/check-schema-versions.sh"   # cached vs latest npm version
bash "$CLAUDE_PLUGIN_ROOT/scripts/check-installed-nodes.sh"   # which installed community nodes lack a schema
```

The coverage check queries `/api/v1/community-packages` on your n8n instance — only present on installations with community-package management enabled. On instances where the endpoint 404s, the check skips silently. Requires `.env` with `N8N_API_URL` and `N8N_API_KEY`.

## Notes

- Schemas are committed to git — they persist across sessions and are part of the workspace.
- Existing schema files are overwritten on each run (intentional — fresh data each time).
- `packageVersion` field tracks which npm version was used; the staleness check reads it.
- Stage 2 writes a `packageName` field so the staleness/coverage checks know which npm package to query.
