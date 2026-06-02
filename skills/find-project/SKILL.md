---
name: find-project
description: List all n8n projects visible on the active instance, showing which one the workspace is pinned to. Use whenever the user asks "which projects exist", "list n8n projects", "show projects on instance", or before pinning a workspace to a different project. Derives projects from `credential list` + `workspace status` — works without Enterprise REST `/projects` endpoint.
argument-hint: "[--name <filter>] [--json]"
user-invocable: true
allowed-tools: Bash(node:*), Bash(npx:*)
---

# Find Project

**Multi-project visibility for the active n8n instance.**

```bash
node "$CLAUDE_PLUGIN_ROOT/skills/find-project/scripts/list.js" "$ARGUMENTS"
```

## What it does

1. Reads `npx n8nac workspace status --json` → active project pin.
2. Reads `npx n8nac credential list --json` → derives the set of projects that own any credential (n8n public API does not expose `/projects` directly outside Enterprise).
3. Prints a table of all visible projects with counts, marks the active one.
4. Surfaces the commands to switch the workspace pin.

## Output shape

```
Active project pin: Personal (BFOi3Ip4tIRPFnMg)

Projects visible on https://n8n.example.com:

  ID                Name                Credentials  Active pin?
  ----------------  ------------------  -----------  -----------
  BFOi3Ip4tIRPFnMg  Personal            14           ← active
  NhVwnjvOp5c5687N  Shared Project      21
  abcDEF1234567890  Marketing Ops       7

To switch the workspace to a different project:
  npx n8nac workspace set-project --project-name "Shared Project"
  npx n8nac workspace set-project --project-id "NhVwnjvOp5c5687N"

After switching, re-run /n8n-autopilot:check-mcps to verify the new scope.
```

## Why this skill exists

A common class of incidents: agents reference credentials from the wrong project because they cannot enumerate projects via the n8n public API. `workspace status` only shows the *active* pin, not the alternatives. This skill derives the full project set from credential ownership and surfaces the exact switch command.

## Exit codes

- `0` — listing printed
- `1` — workspace not bound / n8nac CLI failure
