---
name: inventory
description: Read-only inventory of local n8n workflows — aggregates node-type usage, LLM models, credentials, and trigger types into `docs/INVENTORY.md`. Use when planning new workflows, auditing instance consistency, or onboarding to an existing n8n project.
argument-hint: "[--json] [--dry-run]"
user-invocable: true
allowed-tools: Bash(node:*), Bash(npx:*)
---

# n8n Workflow Inventory

All work happens in `scripts/aggregate.js` (colocated). The skill body is short on purpose — read the script's `--help` for the full flag reference.

## How to invoke

Always call the bundled script. Do not improvise grep/awk pipelines.

```bash
node "$CLAUDE_PLUGIN_ROOT/skills/inventory/scripts/aggregate.js" [flags]
```

| Flag | Meaning |
|------|---------|
| (none) | Aggregate everything in `workflows/**/*.workflow.ts`, write `docs/INVENTORY.md` |
| `--json <path>` | Also write a machine-readable JSON twin (e.g. `--json docs/inventory.json`) |
| `--dry-run` | Print the markdown report to stdout, do not write files |
| `--markdown <path>` | Override the markdown output path (default `docs/INVENTORY.md`) |
| `--workspace <dir>` | Workspace root (default: current directory) |

The script walks `workflows/**/*.workflow.ts`, extracts:

- **Node types** (core `n8n-nodes-base.*`, community `@scope/n8n-nodes-*`, plain `n8n-nodes-*`)
- **Triggers** (anything matching `*Trigger`, `webhook`, `schedule`, `chatTrigger`, `formTrigger`, `mcpTrigger`, `manualTrigger`, `errorTrigger`)
- **LLM models** (literal `value: 'gpt-…' / 'claude-…' / 'llama…' / 'gemini…' / 'mistral…' / 'o1…'`)
- **Credentials** (`credentials: { <type>: …`)
- **Workflow names** (from `@workflow({ name: '…' })`)

It best-effort calls `npx n8nac list --json --include-archived` to enrich the Summary header with remote counts; skips that section silently if n8nac is unbound or offline.

## Output structure

```
# n8n Workflow Inventory

## Summary             — local file count + remote total/active/archived
## Trigger Distribution
## Node Usage — Core   — top 30 by count
## Node Usage — Community
## LLM Models          — provider + model + count
## Credentials         — type + count + 3 example workflow names
```

## Companion scripts

- `scripts/aggregate.js` — the only one. Self-contained Node script, no `--strict --json` deps, runs anywhere Node ≥ 18 does.
