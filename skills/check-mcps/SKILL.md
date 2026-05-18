---
name: check-mcps
description: Check n8nac MCP connection and n8nac config — verifies infrastructure reachability AND tool registration in the active Claude context.
argument-hint: ""
user-invocable: true
allowed-tools: Bash(npx:*), Bash(bash:*), ToolSearch, mcp__n8n-as-code__search_n8n_knowledge
---

# Check n8nac MCP

Two-layer check for the `n8n-as-code` MCP server configured in `.mcp.json`:

- **Layer 1 — Infrastructure** (Bash): Is n8nac reachable? Is the n8n API reachable?
- **Layer 2 — Tool Registration**: Are the n8nac MCP tools registered in the active Claude context?

## Step 1 — Infrastructure check (Bash)

Verify n8nac CLI availability:
```bash
npx n8nac --version 2>&1 | head -3
```

Run the setup script:
```bash
bash scripts/setup-check.sh 2>&1
```

Show the full output. Note OK / WARN / ERROR lines.

## Step 2 — n8nac MCP tool registration

Call `mcp__n8n-as-code__search_n8n_knowledge` with query `"trigger"` and limit `1`.

- If it returns results → **REGISTERED & WORKING**
- If it throws / is unavailable → **NOT REGISTERED**

Optionally use `ToolSearch` with query `"+n8n-as-code"` (max_results: 10) to list all registered n8nac MCP tools.

## Step 3 — Report

```
MCP            | Infra | Tools in Context | Note
───────────────┼───────┼──────────────────┼─────────────────────────────
n8n-as-code    |  OK   |  ✅ registered   |
```

For ❌ or ⚠️ entries, add a short diagnosis and most likely fix:

**n8n-as-code not registered:**
> n8nac MCP server not loaded. Likely causes:
> 1. `.mcp.json` missing the `n8n-as-code` block
> 2. `npx --yes n8nac mcp` failing (network or npm cache issue)
> Fix: Verify `.mcp.json`, run `npx clear-npx-cache && npx n8nac@latest --version`, restart Claude session.

**n8n API unreachable:**
> Check `n8nac-config.json` for correct `host` URL, and verify n8n instance is running.
