---
name: find-credential
description: Search credentials on the active n8n instance by name pattern, scoped to a project. Use whenever the user asks "find credential X", "which credential is …", "list Dropbox/OpenAI/etc. credentials", or before referencing a credential ID in a workflow. Default scope = workspace-pinned project. Returns id, type, project, owner role, and a paste-ready TypeScript snippet.
argument-hint: "<name-pattern> [--type <credType>] [--project <name|id|all>] [--exact]"
user-invocable: true
allowed-tools: Bash(node:*), Bash(npx:*)
---

# Find Credential (Project-Aware)

**One command. No fishing through `--help`.**

```bash
node "$CLAUDE_PLUGIN_ROOT/skills/find-credential/scripts/search.js" "$ARGUMENTS"
```

## What it does

1. Reads workspace status → resolves active project (`projectId`, `projectName`).
2. Calls `npx n8nac credential list --json` (read-only, no secrets).
3. Filters by:
   - **name pattern** (substring, case-insensitive; `--exact` for strict match)
   - **type** (e.g. `dropboxOAuth2Api`) — optional
   - **project scope**: default = workspace-pinned project; `--project all` shows everything; `--project <name|id>` overrides
4. Prints a table grouped by project + paste-ready TypeScript credential blocks.

## Output shape

```
Active project (workspace pin): Confidential RAG (NhVwnjvOp5c5687N)

Matches for "stella" in project Confidential RAG:

ID                  Type                Name                Owner role
------------------  ------------------  ------------------  ----------------
TrPu8rXCuoxpTfnX    dropboxOAuth2Api    Dropbox Stella2     credential:owner
pVsHmMxpQZaUui5w    dropboxOAuth2Api    Dropbox stella 2    credential:owner

TypeScript snippet:
  credentials: { dropboxOAuth2Api: { id: "TrPu8rXCuoxpTfnX", name: "Dropbox Stella2" } }
  credentials: { dropboxOAuth2Api: { id: "pVsHmMxpQZaUui5w", name: "Dropbox stella 2" } }

Other projects with "stella" matches (hidden — use --project all to see):
  Personal (BFOi3Ip4tIRPFnMg): 1 match
```

## Common invocations

| User says | Command |
|---|---|
| "find Stella credential" | `/n8n-autopilot:find-credential stella` |
| "list all Dropbox creds in this project" | `/n8n-autopilot:find-credential "" --type dropboxOAuth2Api` |
| "show all OpenAI creds across the whole instance" | `/n8n-autopilot:find-credential openai --project all` |
| "exact cred name 'Dropbox Stella2'" | `/n8n-autopilot:find-credential "Dropbox Stella2" --exact` |

## Project scope rules

- **Default = active workspace project.** Hides matches in other projects (shown as summary footnote).
- **`--project all`** shows everything, grouped by project.
- **`--project <name>`** filters to that project (matched against `shared[].name`).
- **`--project <id>`** filters by project ID.

This is the canonical way to look up a credential before referencing it in a `.workflow.ts`. Do NOT fall back to `n8nac credential list --json | grep` — it skips project-scoping and leaks cross-project IDs into workflows.

## Why this skill exists

`n8nac credential list --json` returns every credential the API key can see across all projects. Without project-scoping, agents pick the first matching name and inject an ID that belongs to another project — the workflow then fails at runtime with "credential not accessible". This skill enforces project-scope by default.

## Exit codes

- `0` — matches found and printed
- `1` — workspace not bound / n8nac CLI failure
- `2` — no matches in active project (footnote shows counts in other projects if any)
