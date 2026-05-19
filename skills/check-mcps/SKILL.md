---
name: check-mcps
description: Verify n8n-autopilot setup is functional — n8nac CLI present, workspace bound, n8n API reachable, companion plugin `n8n-as-code@n8nac-marketplace` enabled. Use after setup, after upgrading the plugin, or when commands behave unexpectedly.
argument-hint: ""
user-invocable: true
allowed-tools: Bash(npx:*), Bash(bash:*), Bash(grep:*), Bash(test:*)
---

# Check n8n-autopilot Setup

n8n-autopilot is CLI-only (`npx n8nac …`). There is no MCP server entry for this plugin — the `mcp__n8n-as-code__*` namespace seen in older docs was an upstream assumption that never landed (the npm `n8nac mcp` entry-point is broken and Etienne's companion plugin ships skill knowledge, not an MCP server).

This skill verifies the actually-required layers.

## Step 1 — n8nac CLI reachable

```bash
npx n8nac --version 2>&1
```

Expect `2.2.0` or higher. Anything below is unsupported.

## Step 2 — Full health check via setup-check.sh

```bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/setup-check.sh" 2>&1
```

(`$CLAUDE_PLUGIN_ROOT` is set by Claude Code when running plugin commands — no manual path needed.)

Inspect the output. The script checks, in order:

1. `npx` available
2. n8nac CLI version vs minimum/reference
3. n8nac workspace bound (`workspace status --json` returns env config)
4. n8n API reachable (host pulled from the workspace status JSON)
5. Companion plugin `n8n-as-code@n8nac-marketplace` enabled (warns if missing — the companion's `n8n-architect` skill is the primary source of n8n authoring knowledge)
6. Community-node schema coverage
7. Inventory freshness (informational)

## Step 3 — Companion plugin (`n8n-as-code`) enabled

```bash
grep -q '"n8n-as-code@n8nac-marketplace": true' "$HOME/.claude/settings.json" && \
  echo "OK: n8n-as-code companion enabled" || \
  echo "WARN: n8n-as-code companion not enabled — install it for best UX:
  claude plugin marketplace add EtienneLescot/n8n-as-code
  claude plugin install n8n-as-code@n8nac-marketplace"
```

## Step 4 — Report

Print a one-line summary per layer, plus the most likely fix for any FAIL:

```
Layer                              | Status
───────────────────────────────────┼─────────
n8nac CLI (>= 2.2.0)                |  OK
workspace bound                     |  OK
n8n API reachable                   |  OK
companion plugin (n8n-as-code)      |  OK
schemas/_index.json present         |  OK
```

For any non-OK row, surface the line from `setup-check.sh` verbatim — that script already prints the suggested fix.
