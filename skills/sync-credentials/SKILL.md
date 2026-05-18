---
name: sync-credentials
description: Sync credential IDs from the live n8n instance. Two modes — list (default) reports IDs, fix-workflows rewrites stale credential IDs in local .workflow.ts files by matching on credential name. Use after n8n migration, when setting up a new instance, or in response to a credential-freshness auto-reaction signal.
argument-hint: "[--dry-run] [--add-missing] [--fix-workflows]"
user-invocable: true
allowed-tools: Read, Edit, Write, Grep, Glob, Bash(npx:*), Bash(find:*), Bash(grep:*), Bash(bash:*)
---

# Sync Credentials from n8n Instance

Pull credential IDs from the live n8n instance and either report them or repair stale references in local workflow files.

## Modes

| Flag | What it does |
|------|--------------|
| (none) | List all live credentials in a table. Read-only. |
| `--dry-run` | Same as list mode (alias, kept for clarity). |
| `--add-missing` | Update `docs/CREDENTIALS.md` — replace `REPLACE_WITH_...` placeholders with live IDs by matching on `credentialTypeName`. |
| `--fix-workflows` | Scan `workflows/**/*.workflow.ts` and rewrite credential IDs that no longer resolve on the instance. Join key is the credential **name** inside the `credentials: { <type>: { id, name } }` block. **This is what the credential-freshness auto-reaction triggers.** |

## Prerequisites

- n8nac initialized (`npx n8nac init`)
- At least one credential configured on the n8n instance

## Steps

### 1. Health Check

```bash
npx n8nac list --remote --json
```

If the command fails, the instance is unreachable — stop and report.

### 2. Fetch Live Credentials

```bash
npx n8nac credential list --json
```

Parse into `{ type, id, name }` tuples.

### 3a. List Mode (default / `--dry-run`)

Print a summary table:

```
Credential Type        ID               Name
──────────────────────────────────────────────────
openAiApi              MrTjCy4MBxfeDila OpenAI account
slackOAuth2Api         fgEYaDirOTV5nGhJ Slack account
```

Plus ready-to-paste TypeScript snippets:

```typescript
credentials: { openAiApi: { id: "MrTjCy4MBxfeDila", name: "OpenAI account" } }
```

Stop after the table.

### 3b. `--add-missing` Mode

Read `docs/CREDENTIALS.md`. For each entry with a `REPLACE_WITH_...` ID placeholder, match against the live list by `credentialTypeName` (1:1 unique). Update ID + name inline. Preserve file structure, ordering, and unmatched entries.

### 3c. `--fix-workflows` Mode

**Goal:** Repair every workflow file that references a credential ID which does not exist on the live instance, by looking up the new ID by name.

1. Build a lookup map from the live credentials: `name → {id, type}`.

2. Find all `.workflow.ts` files:
   ```bash
   find workflows -name "*.workflow.ts" -type f
   ```

3. For each file, extract every `credentials: { <type>: { id: '<oldId>', name: '<credName>' } }` block. Use a tolerant regex — the order of `id` / `name` may vary. Recommended approach: `node` script with proper TS-source parsing of the credential blocks rather than line-by-line `sed`.

4. For each `(type, oldId, credName)` triplet:
   - Look up `credName` in the live map.
   - If the live entry's `id` differs from `oldId` → this is a stale reference, schedule a rewrite.
   - If the live entry's `type` differs from the workflow's `type` → stop and report ambiguity. Do NOT rewrite type. The user must decide.
   - If `credName` has no match on the live instance → report as orphan, do NOT rewrite. Suggest user creates the credential or removes the reference.

5. Apply rewrites in-place. Use the `Edit` tool to replace `id: '<oldId>'` within each matched block — do NOT replace across the whole file (the same ID string could appear elsewhere coincidentally).

6. Report:
   ```
   ✅ Updated 3 credential reference(s) in 2 workflow file(s):
      workflows/foo.workflow.ts     openAiApi  → MrTjCy4MBxfeDila
      workflows/foo.workflow.ts     slackOAuth2Api → fgEYaDirOTV5nGhJ
      workflows/bar.workflow.ts     postgres  → kwK3oFcfQVS61bDh

   ⚠️  1 orphan(s) — credential name has no match on the live instance:
      workflows/legacy.workflow.ts  pandadocApi name='PandaDoc old'
        → create the credential on the instance or remove the reference
   ```

7. After successful rewrites, re-run the freshness check to confirm:
   ```bash
   bash "$(claude plugin path n8n-autopilot)/scripts/check-credential-freshness.sh"
   ```

### 4. Show Usage

Always end with the copy-paste TypeScript snippets so the user can verify or use them for new workflows.

## Error Handling

- **n8nac not initialized** → stop, tell user to run `npx n8nac init`
- **No credentials on instance** → report, suggest creating credentials in n8n UI first
- **Ambiguous match** (same credential name appears multiple times on instance) → report all candidates, do NOT auto-pick
- **Type mismatch** (workflow uses `openAiApi`, live credential with that name is `openRouterApi`) → stop, report, do not rewrite

## Example Invocations

```
/n8n-autopilot:sync-credentials                    # List live credentials
/n8n-autopilot:sync-credentials --dry-run          # Same as above (explicit)
/n8n-autopilot:sync-credentials --add-missing      # Patch docs/CREDENTIALS.md placeholders
/n8n-autopilot:sync-credentials --fix-workflows    # Rewrite stale credential IDs in workflows/
```

## Auto-Reaction Source

`check-credential-freshness.sh` (SessionStart hook) emits:

```
AUTOPILOT_ACTION_REQUIRED: /n8n-autopilot:sync-credentials --fix-workflows
```

when it detects workflow files referencing credential IDs that don't exist on the live instance. The skill MUST run with `--fix-workflows` in that case — listing alone does not resolve the underlying problem.
