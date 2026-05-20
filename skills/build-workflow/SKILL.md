---
name: build-workflow
description: "Full 3-phase pipeline (Research → Write+Validate → Deploy+Test) for shipping an n8n workflow end-to-end. Wraps Etienne's `n8n-as-code:n8n-architect` skill for schema research + authoring, adds repo-scoped orchestration — community-template lookup, validate-push-test loop, mcpTrigger publish gate, execution inspection, Completion Report."
argument-hint: '"Description of what the workflow should do"'
user-invocable: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(npx:*), Bash(grep:*), Bash(node:*), Bash(npm:*), Bash(find:*), Bash(cat:*), Bash(jq:*), Bash(mkdir:*)
---

# Build Workflow (Full Pipeline)

Take a natural-language description and ship it as a **verified live execution on n8n**. All three phases are mandatory. The skill is only complete after a successful execution has been inspected and reported.

> **Companion plugin required.** This skill leans on `n8n-as-code:n8n-architect` (from the `n8nac-marketplace` plugin by Etienne Lescot) for schema research, authoring rules, and n8n best practices — installing `n8n-autopilot` without the companion plugin will work but you will miss the shared knowledge base. Install both:
>
> ```bash
> claude plugin marketplace add EtienneLescot/n8n-as-code
> claude plugin install n8n-as-code@n8nac-marketplace
> ```

## Tools — all CLI

n8n-autopilot is CLI-only (`npx n8nac …`). There is no `mcp__n8n-as-code__*` namespace in any working setup — the npm `n8nac mcp` entry-point is broken upstream and Etienne's plugin ships skill knowledge, not an MCP server. Use the table below.

| Command | Role |
|---------|------|
| `npx n8nac skills examples search "<q>"` / `info <id>` / `download <id>` | Community-template lookup (7000+ from n8nworkflows.xyz) — **always Step 0** |
| `npx n8nac skills search "<q>"` / `node-info <name> --json` / `node-schema <name> --json` | Node discovery + exact TypeScript defs from local schemas |
| `npx n8nac skills related "<q>"` / `guides "<q>"` | Alternative nodes + tutorials |
| `npx n8nac skills validate <file> --strict --json` | Local workflow validation |
| `npx n8nac push <file> --verify` | Deploy + remote-state verification in one call |
| `npx n8nac test-plan <id> --json` | Infer triggerType + suggestedPayload before testing |
| `npx n8nac test <id> --data '...'` | HTTP-trigger live test (webhook/chat/form) |
| `npx n8nac execution get <execId> --include-data` | Inspect execution output |
| `npx n8nac find <q> --json --remote` | Search existing remote workflows |
| `npx n8nac workflow present <id> --json` | Resolve the user-facing n8n URL — never string-concat `<host>/workflow/<id>` |
| `npx n8nac workflow credential-required <id>` | Check credential readiness (exit 0 = all present, exit 1 = missing) |

**Limits:** `n8nac test` cannot fire schedule/manual/errorTrigger workflows (user runs "Execute Workflow" in the n8n UI). n8nac cannot publish drafts (mcpTrigger workflows need manual UI publish).

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

**Goal:** Know exact node types, parameter names, and SDK patterns before writing code. Delegate schema-research details to the companion `n8n-architect` skill — it owns Schema-First Research, Workflow Authoring Rules, AI/LangChain rules, Common Mistakes.

**Step 0 — Community-template lookup (MANDATORY before any node-by-node work):**
```bash
npx n8nac skills examples search "<2-3 keywords from the description>" --json
```
Inspect top hits with `npx n8nac skills examples info <id>`. If a template matches the requested workflow by ≥70 % (same trigger family + same target service + comparable transformations), download it as the starting point:
```bash
npx n8nac skills examples download <id>
```
Then jump to Phase 1 step 1 with the downloaded file as the seed and only run Steps 1–2 below for nodes you add or change. Adapting an existing template is cheaper, less hallucination-prone, and lands on a community-proven pattern.

**Step 1 — Node discovery (CLI-only):**
```bash
npx n8nac skills search "<service>" --json     # find candidate nodes
npx n8nac skills node-info <type> --json       # exact parameters, credential keys, typeVersion
npx n8nac skills related "<service>" --json    # alternatives + nearest docs
```
For AI agents/memory/vector stores also check `npx n8nac skills guides "<topic>"`.

**Step 2 — Code-Node specifics (only if the workflow uses Code nodes):**
- Skill `n8n-code-javascript` covers `$input` / `$json` / `$node` / `$helpers.httpRequest()` / DateTime (Luxon) / top mistakes
- Skill `n8n-code-python` covers `_input` / `_json` / standard library only

**Step 3 — Find similar existing workflows (optional):**
```bash
npx n8nac find <query> --json --remote
```

**Gate:** Do not proceed to Phase 1 without verified parameter names for every node. **Never guess** — wrong keys are silently ignored by n8n at runtime.

> **Missing schema?** If `npx n8nac skills node-info <type>` returns empty or not-found for a community node:
> 1. Look up the npm package name in `docs/COMMUNITY_NODES.md` (Package column)
> 2. Run Stage 3 extraction immediately (see `/n8n-autopilot:pull-schemas` skill) for that package
> 3. Rebuild `schemas/_index.json`
> 4. Then re-run `skills node-info` — or read the cached schema directly from `schemas/nodes/`
>
> A missing schema is always recoverable via Stage 3.

### Phase 1 — Write + Validate

1. Pull the closest existing workflow as starting point (optional, only if Step 0 / Step 3 surfaced a useful one):
   ```bash
   npx n8nac pull <workflowId>
   ```
   Or create a new `.workflow.ts` file from scratch in Decorator-TS format.

2. Write `workflows/<name>.workflow.ts` using Decorator-TS format. The companion `n8n-architect` skill documents the full authoring rules — these conventions are repo-specific additions on top:
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

3. Validate locally — single source of truth:
   ```bash
   npx n8nac skills validate workflows/<name>.workflow.ts --strict --json
   ```
   Fix any errors → re-validate. Do not push with errors.

4. Push + verify in one call:
   ```bash
   npx n8nac push workflows/<name>.workflow.ts --verify
   ```
   `--verify` fetches the workflow from n8n after push and validates it against the local schema. On mismatch: re-push. On success: proceed to Phase 2.

**Gate:** Local validation passes + push succeeds + verify passes. Fix and retry if needed.

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

`n8nac test` calls the test URL (`/webhook-test/`) — no activation needed.

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

3. On Class A error (exit 0): inform user about missing credentials/model — do not block.
4. On Class B error (exit 1): fix workflow → re-validate → re-push (`--verify`) → re-test (max 3 cycles).

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

`n8nac` cannot trigger these — manual test required. Stop the auto-pipeline here and prompt the user:

1. Check credential presence (same as Path A step 1).

2. Resolve the user-facing URL via the CLI (do not string-concat):
   ```bash
   npx n8nac workflow present <workflowId> --json
   ```

3. Display to user (prominent), using the URL from step 2:
   ```
   ⚠️  MANUAL TEST REQUIRED — non-HTTP trigger

   Open n8n UI:  <url from workflow present>
   Click:        "Execute Workflow" button (top right)
   Then report back: execution-id (visible in the executions panel)
   ```

4. Once the user reports an execution-id, inspect results:
   ```bash
   npx n8nac execution get <executionId> --include-data
   ```
   Check `status`, node outputs, error messages.

5. On error: fix workflow → re-validate → re-push (`--verify`) → ask user to re-execute in UI (max 3 cycles).

#### Path C — Activate for production (optional)

After successful test, if the user wants the workflow active (cron starts running, webhook becomes available on the production URL):
```bash
npx n8nac workflow activate <workflowId>
```

Note: `activate` is NOT the same as `publish` for the new Two-Phase model — see Path D for `mcpTrigger` workflows.

#### Path D — Manual Publish required (when `HAS_MCP_TRIGGER=true`)

n8nac cannot publish drafts. After a successful push of an `mcpTrigger` workflow:

1. Resolve URL: `npx n8nac workflow present <workflowId> --json`
2. Display to user (prominent), using that URL:

```
⚠️  MANUAL PUBLISH REQUIRED — mcpTrigger detected

The MCP endpoint will return 404 until the workflow is published.

Open n8n UI:  <url from workflow present>
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
**URL:** [from `npx n8nac workflow present <id> --json`]
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
| 0 | `npx n8nac skills node-info` returns empty for a community node | Run Stage 3 (npm extraction, see `/n8n-autopilot:pull-schemas`) → rebuild index → read from `schemas/nodes/` |
| 0 | Schema-research stuck on parameter ambiguity | Defer to `n8n-as-code:n8n-architect` skill — it has authoritative rules for resource/operation discriminators |
| 1 | Local validation fails | Fix code → re-validate |
| 1 | Push fails (conflict) | `npx n8nac list` → `npx n8nac resolve <id>` → retry |
| 1 | Push fails (archived) | Workflow is archived → read-only. Do not iterate — inform user: unarchive in n8n UI or create a new workflow |
| 1 | Verify fails (remote mismatch) | Re-push → re-verify |
| 2A | Class A error (exit 0) | Report missing credentials to user — do not iterate |
| 2A | Class B error (exit 1) | Fix workflow → re-validate → re-push (`--verify`) → re-test (max 3 cycles) |
| 2B | Manual UI execution fails | `npx n8nac execution get <id> --include-data` for error details → fix → re-push → ask user to re-execute |
