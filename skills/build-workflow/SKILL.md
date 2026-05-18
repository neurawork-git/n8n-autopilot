---
name: build-workflow
description: Full 3-phase pipeline (Research → Write+Validate → Deploy+Test) — research, write+validate, deploy+test a workflow on n8n. Use when the user wants an end-to-end workflow that is deployed and verified on the n8n instance.
argument-hint: '"Description of what the workflow should do"'
user-invocable: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(npx:*), Bash(grep:*), Bash(node:*), Bash(npm:*), Bash(find:*), Bash(cat:*), Bash(jq:*), Bash(mkdir:*), Agent, mcp__n8n-as-code__*
---

# Build Workflow (Full Pipeline)

Create a workflow from description to **verified live execution on n8n**. All phases are mandatory. The skill is only complete when the workflow has been tested and a completion report is delivered.

## Tools

This skill uses **n8nac only** (CLI + `n8n-as-code` MCP):

| Tool | Role |
|------|------|
| `mcp__n8n-as-code__search_n8n_knowledge`, `get_n8n_node_info`, `validate_n8n_workflow` | Node discovery, parameter lookup, JSON validation |
| `npx n8nac skills node-info <name> --json` / `skills node-schema --json` | Exact TypeScript defs from local schemas/ cache |
| `npx n8nac skills validate <file> --strict --json` | Local workflow validation |
| `npx n8nac push <file> --verify` | Deploy + remote-state verification |
| `npx n8nac test <id> --data '...'` | HTTP-trigger test (webhook/chat/form) |
| `npx n8nac execution get <execId> --include-data` | Inspect execution output |
| `npx n8nac find <query> --json --remote` | Search existing workflows |

**Limits:** n8nac cannot trigger schedule/manual/errorTrigger workflows (user must run "Execute Workflow" in n8n UI), and cannot publish drafts (mcpTrigger workflows need manual UI publish).

## Input

`$ARGUMENTS` = natural-language description of the workflow. Extract:
- **Trigger type**: webhook, schedule, error, manual, chat, telegram
- **Action**: what the workflow does
- **Target**: which service/API is involved
- **AI components**: agent, model, memory, tools?
- **Test data**: what input should the live test use?

If `$ARGUMENTS` is empty, ask the user before proceeding.

## Pipeline

### Phase 0 — Research

**Goal:** Know exact node types, parameter names, and SDK patterns before writing code.

**Step 1 — n8nac node discovery** (launch `n8n-researcher` agent, haiku):
- `search_n8n_knowledge` for each service involved
- `get_n8n_node_info` for each node type → exact parameters + credential keys

**Step 2 — Exact TypeScript defs + SDK patterns:**
- `npx n8nac skills node-info <node-name> --json` for each node from Step 1 → exact parameters, credential keys, version
- Skills `n8n-workflow-patterns`, `n8n-expression-syntax`, `n8n-node-configuration` for SDK coding rules and expression syntax
- `npx n8nac skills guides "<query>"` for relevant tutorials
- `npx n8nac skills related "<query>"` — use when the workflow involves AI agents, memory, or vector stores (pattern recommendations)

**Step 3 — Check existing workflows (optional):**
- `npx n8nac find <query> --json --remote` to find similar existing workflows as reference patterns

**Gate:** Do not proceed to Phase 1 without verified parameter names for every node.

> **Missing schema?** If `get_n8n_node_info` returns empty or not-found for a community node:
> 1. Look up the npm package name in `docs/COMMUNITY_NODES.md` (Package column)
> 2. Run Stage 3 extraction immediately (see `pull-schemas` skill) for that package
> 3. Rebuild `schemas/_index.json`
> 4. Then re-run `get_n8n_node_info` — or read the cached schema directly from `schemas/nodes/`
>
> Do **not** guess parameter names. A missing schema is always recoverable via Stage 3.

### Phase 1 — Write + Validate

1. Pull closest existing workflow as starting point (optional):
   ```bash
   npx n8nac pull <workflowId>
   ```
   Or create a new `.workflow.ts` file from scratch in Decorator-TS format.

2. Write `workflows/<name>.workflow.ts` using Decorator-TS format:
   - `@workflow({...})` decorator with name and settings
   - Each node as a class method with `@node({...})` or `@trigger({...})`
   - `@links()` method for connections
   - Sticky note node documenting purpose + required credentials
   - Use `={{ $json.fieldName }}` for n8n runtime expressions
   - Use verified parameter names from Phase 0
   - ResourceLocator parameters use `{ __rl: true, value: "...", mode: "list" }`

   **Naming + documentation conventions:**
   - Workflow names: `[Trigger] Action - Target` (e.g. `[Webhook] Create Lead - Close CRM`)
   - Node names: Verb + Object (e.g. `Validate Input`, `Fetch Users`, `Send Alert`)
   - File: `<workflow-name>.workflow.ts` in `workflows/` (e.g. `workflows/create-lead.workflow.ts`)
   - Every workflow MUST include a sticky note documenting Purpose + Required Credentials
   - Inline node notes (visible on the canvas without opening the node) — useful for short "why this node exists" explanations:
     ```typescript
     @node({
       name: 'Filter Inactive Users',
       type: 'n8n-nodes-base.filter',
       notes: 'Removes users with status != active before CRM sync',
       notesInFlow: true,    // shows the note on the canvas
       position: [500, 300]
     })
     ```
     `notesInFlow: true` without `notes` has no effect.
   - Every webhook-triggered workflow MUST include a `Respond to Webhook` node — a webhook without a response will hang and time out for the caller.

   > **mcpTrigger rule:** If the workflow uses `@n8n/n8n-nodes-langchain.mcpTrigger`,
   > always set `availableInMCP: true` explicitly in the `@workflow` settings block:
   > ```typescript
   > settings: {
   >   executionOrder: "v1",
   >   callerPolicy: "any",
   >   availableInMCP: true,   // required — prevents n8n API bug #25987 from resetting to false
   > }
   > ```
   > The PreToolUse hook (`ensure-mcp-trigger-setting.sh`) auto-fixes `false → true` and warns
   > when the field is missing entirely, but setting it explicitly here is the canonical source of truth.

3. Launch `workflow-reviewer` agent (sonnet) to review the `.workflow.ts`

4. Local validation:
   ```bash
   npx n8nac skills validate --strict --json workflows/<name>.workflow.ts
   ```

5. Instance validation (dual-check) via n8n-as-code MCP:
   ```
   mcp__n8n-as-code__validate_n8n_workflow(code: <workflow TS content>)
   ```
   Compare results from both. Instance validation catches issues the offline validator may miss (e.g. credential type mismatches, node version constraints on the live instance).

6. Push + verify:
   ```bash
   npx n8nac push workflows/<name>.workflow.ts --verify
   ```
   `--verify` fetches the workflow from n8n after push and validates it against the local schema.
   On mismatch: re-push. On success: proceed to Phase 2.

**Gate:** Both validations pass + push succeeds + verify passes. Fix and retry if needed.

### Phase 2 — Execute + Test (MANDATORY)

> **After every successful push, ALWAYS run Phase 2.** A workflow is only complete once an execution has been inspected (success or Class-A error reported to the user).

#### Step 0 — Trigger classification (automatic, runs before path selection)

1. ```bash
   npx n8nac test-plan <workflowId> --json
   ```
   Extract `triggerType`, `testable`, `suggestedPayload`. Reuse this result in Path A/B — do NOT call `test-plan` again.

2. Check the local `.workflow.ts` for `@n8n/n8n-nodes-langchain.mcpTrigger`:
   ```bash
   grep -l "mcpTrigger\|n8n-nodes-langchain.mcpTrigger" workflows/<name>.workflow.ts
   ```
   Set `HAS_MCP_TRIGGER = true/false`.

3. Routing:
   - `HAS_MCP_TRIGGER=true` → Path D (manual publish notice) added on top of A or B
   - `triggerType ∈ {webhook, chat, form}` → **Path A**
   - `triggerType ∈ {schedule, manual, errorTrigger}` → **Path B**
   - Unknown triggerType → log warning, fall back to Path B (manual UI test)

#### Path A — HTTP-testable triggers (webhook, chat, form)

**n8nac test** calls the test URL (`/webhook-test/`) — no activation needed.

1. Check credential presence:
   ```bash
   npx n8nac workflow credential-required <workflowId>
   ```
   - Exit 0: all present → proceed
   - Exit 1: credentials missing → inform user, do not block

2. Live test (use `suggestedPayload` from Step 0):
   ```bash
   # POST/body webhooks (default):
   npx n8nac test <workflowId> --data '<suggestedPayload>'

   # GET/HEAD webhooks (workflow reads $json.query):
   npx n8nac test <workflowId> --query '<suggestedPayload>'
   ```
   If the user provided specific test data in `$ARGUMENTS`, use that instead.

3. On Class A error (exit 0): inform user about missing credentials/model — do not block
4. On Class B error (exit 1): fix workflow → re-validate → re-push (`--verify`) → re-test (max 3 cycles)

5. Inspect execution results:
   ```bash
   npx n8nac execution get <executionId> --include-data
   ```
   For large outputs, slice with `jq`:
   ```bash
   npx n8nac execution get <executionId> --include-data | jq '.data.resultData.runData["<nodeName>"]'
   ```
   Use the node-level output data in the Completion Report.

#### Path B — Non-HTTP triggers (schedule, manual, errorTrigger, telegram)

**n8nac cannot trigger these — manual test required.** Stop the auto-pipeline here and prompt the user:

1. Check credential presence (same as Path A step 1)

2. Display to user (prominent):
   ```
   ⚠️  MANUAL TEST REQUIRED — non-HTTP trigger

   Open n8n UI:  <n8n_host>/workflow/<workflowId>
   Click:        "Execute Workflow" button (top right)
   Then report back: execution-id (visible in the executions panel)
   ```

3. Once the user reports an execution-id, inspect results:
   ```bash
   npx n8nac execution get <executionId> --include-data
   ```
   Check `status`, node outputs, error messages.

4. On error: fix workflow → re-validate → re-push (`--verify`) → ask user to re-execute in UI (max 3 cycles)

#### Path C — Activate for production (optional)

After successful test, if the user wants the workflow active (cron starts running, webhook becomes available on the production URL):
```bash
npx n8nac workflow activate <workflowId>
```

Note: `activate` is NOT the same as `publish` for the new Two-Phase model — see Path D for `mcpTrigger` workflows.

#### Path D — Manual Publish required (when `HAS_MCP_TRIGGER=true`)

n8nac cannot publish drafts. After a successful push of an `mcpTrigger` workflow, display to user (prominent):

```
⚠️  MANUAL PUBLISH REQUIRED — mcpTrigger detected

The MCP endpoint will return 404 until the workflow is published.

Open n8n UI:  <n8n_host>/workflow/<workflowId>
Click:        "Publish" button
Confirm in the Completion Report once done.
```

> **Reminder:** `npx n8nac push` writes a new draft. The previously-published version stays live, but its MCP endpoint may diverge from the new draft. Each push to an `mcpTrigger` workflow requires a fresh UI publish.

**Gate:** Execution status is `success` or Class A error reported to user. Maximum 3 fix cycles.

## Completion Report

```
## Workflow deployed and verified

**Name:** [Workflow Name]
**ID:** [n8n workflow ID]
**Location:** workflows/<name>.workflow.ts
**trigger_type:** [webhook | schedule | manual | mcpTrigger | ...]
**test_path_used:** [Path A (auto) / Path B (manual UI) / Path D-extended]

**Live test result:**
- execution_id: [ID]
- execution_status: [success / error-class-A / error-class-B]
- Nodes executed: [list with status per node]
- output_sample: [key fields from last node, via `n8nac execution get --include-data`]

**MCP Access:** (only when mcpTrigger is present)
- mcp_endpoint: [URL]
- manually_published: yes / no — user confirmation required

**Files created:**
- workflows/<name>.workflow.ts
```

## Error Recovery

| Phase | Error | Action |
|-------|-------|--------|
| 0 | n8nac MCP unavailable | Fall back to CLI: `npx n8nac skills node-info <name> --json` and `skills search` for discovery |
| 0 | Community node not in n8nac | Run Stage 3 (npm extraction) → rebuild index → read from `schemas/nodes/` |
| 1 | Local validation fails | Fix code → re-validate |
| 1 | Instance validation reports new error | Fix code → re-validate both → re-push |
| 1 | Push fails (conflict) | `n8nac list` → `n8nac resolve` → retry |
| 1 | Push fails (archived) | Workflow is archived → read-only. Do not iterate — inform user: unarchive in n8n UI or create a new workflow |
| 1 | Verify fails (remote mismatch) | Re-push → re-verify |
| 2A | Class A error (exit 0) | Report missing credentials to user — do not iterate |
| 2A | Class B error (exit 1) | Fix workflow → re-validate → re-push (`--verify`) → re-test (max 3 cycles) |
| 2B | Manual UI execution fails | `npx n8nac execution get <id> --include-data` for error details → fix → re-push → ask user to re-execute |
