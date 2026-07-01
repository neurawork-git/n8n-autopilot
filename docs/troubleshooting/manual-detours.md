# Manual Detours — steps n8nac cannot automate

Three lifecycle gaps where n8nac can't finish the job alone. CLAUDE.md links here.

---

## MCP Access Lifecycle (workflows with `mcpTrigger`) — MANUAL

Workflows containing `@n8n/n8n-nodes-langchain.mcpTrigger` expose an MCP endpoint. That endpoint is
reachable ONLY after Publish in the n8n UI. `n8nac push` creates a new Draft — the previously
published version stays live, so the MCP endpoint can be stale relative to the new Draft.

**Rule:** after every push/update of a workflow with `mcpTrigger`:
1. Resolve the URL: `npx n8nac workflow present <workflowId> --json`
2. Open the n8n UI at that URL
3. Click "Publish"
4. User confirms publish status in the Completion Report

n8nac cannot publish. The `deploy` skill and Phase 2 (Path D) of the `build-workflow` pipeline show
a prominent hint instead of auto re-publishing.

---

## Non-HTTP-Trigger Testing — MANUAL

`npx n8nac test` can only fire Webhook / Chat / Form triggers. For `schedule`, `manual`,
`errorTrigger`:

→ **`/n8n-autopilot:test-manual <workflowId>`** bundles the whole detour (resolve URL → wait for
execution-id → inspect run). The manual steps:

1. Resolve the URL: `npx n8nac workflow present <workflowId> --json`
2. Open the n8n UI at that URL
3. Click "Execute Workflow"
4. User reports the `execution-id` to Claude
5. Claude inspects via `npx n8nac execution get <id> --include-data`

The `build-workflow` pipeline (Path B) stops automatically and prompts the user accordingly.

---

## DataTable Lifecycle (curl carve-out)

n8nac has no `datatable` subcommand. Managing DataTable resources (create/list/seed/drop tables,
columns, rows) is done via the n8n public REST API at `/api/v1/data-tables`. The PreToolUse
curl-block has an explicit carve-out for this path only.

→ Use the `/n8n-autopilot:data-tables` skill — it documents every endpoint and provides
ready-to-paste curl recipes (incl. heredoc-safe JSON for umlauts on Windows), plus the upsert node
shape (3-part requirement) + usage patterns (fan-in store, idempotency/dedup, error rows).
