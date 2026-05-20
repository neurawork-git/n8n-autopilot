---
name: sync-credentials
description: Sync credential IDs from the live n8n instance. Two modes — list (default) reports IDs + TypeScript snippets, fix-workflows rewrites stale credential IDs in local `.workflow.ts` files by joining on credential name. Use after n8n migration, when setting up a new instance, or in response to a credential-freshness auto-reaction signal.
argument-hint: "[--dry-run] [--fix-workflows]"
user-invocable: true
allowed-tools: Bash(node:*), Bash(npx:*)
---

# Sync Credentials from n8n Instance

All work happens in `scripts/` (colocated). The skill body is short on purpose — the scripts are the source of truth.

## Modes

### Default — list live credentials

```bash
node "$CLAUDE_PLUGIN_ROOT/skills/sync-credentials/scripts/list.js"
```

Prints a table of all credentials on the active n8n instance plus ready-to-paste TypeScript snippets. Read-only.

### `--fix-workflows` — rewrite stale credential IDs

```bash
node "$CLAUDE_PLUGIN_ROOT/skills/sync-credentials/scripts/fix-workflows.js" [--dry-run] [--all-projects]
```

Walks `workflows/**/*.workflow.ts`, finds every `credentials: { <type>: { id: '…', name: '…' } }` block, joins by credential **name** against the live instance **filtered to the workspace-pinned project**, and rewrites the `id` value where the live ID differs from the local one. Order of `id` / `name` inside the block is tolerated; type mismatches and orphans are reported and NOT auto-rewritten.

**Project scoping (default):** credentials owned by projects other than the active workspace project are dropped from the candidate pool. This prevents cross-project ID injection that would push fine but fail at runtime ("credential not accessible"). Use `--all-projects` to disable the filter (rare).

Add `--dry-run` to preview without writing files.

This is what the SessionStart credential-freshness auto-reaction triggers:

```
AUTOPILOT_ACTION_REQUIRED: /n8n-autopilot:sync-credentials --fix-workflows
```

## Companion scripts

- `scripts/list.js` — fetches credentials via `npx n8nac credential list --json`, prints table + snippets
- `scripts/fix-workflows.js` — the rewrite logic. Self-contained Node script, tolerant block-parsing regex, surgical `id:` replacement inside each matched block (never global), conflict + orphan reporting.

## Prerequisites

- n8nac workspace bound. Check via `npx n8nac workspace status --json`. If not bound, run `npx n8nac setup --mode connect-existing` first.
- At least one credential configured on the live instance (or create one via `npx n8nac credentials ensure <recipeId>` from the shared recipe catalogue).

## Error Handling

- **`n8nac credential list` fails** → script exits 1 with a hint to check `workspace status`.
- **No `.workflow.ts` files** → script exits 2 with a hint.
- **Type mismatch** (workflow says `openAiApi`, live credential with that name is `openRouterApi`) → reported as conflict, NOT rewritten.
- **Duplicate name on instance** (same credential name appears twice live) → reported as conflict, NOT rewritten — user must rename one on the instance.
- **Orphan** (workflow references a name that does not exist on live instance) → reported, NOT rewritten — user creates the credential or removes the reference.

## When to auto-trigger this skill

The SessionStart hook `scripts/check-credential-freshness.sh` (plugin-wide, not in this skill folder — it is a generic plugin hook) emits the auto-reaction line above when it detects local workflow files referencing credential IDs that do not exist on the live instance. Run with `--fix-workflows` in that case — `list` alone does not resolve the underlying problem.
