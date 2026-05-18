---
name: deploy
description: Push a local .workflow.ts to n8n, then activate and live-test it. Only invoked manually via /deploy.
argument-hint: "<workflow-name>.workflow.ts [--activate] [--prod]"
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash(npx:*), Bash(grep:*), mcp__n8n-as-code__validate_n8n_workflow
---

# Deploy Workflow

Push a local `.workflow.ts` to n8n via n8nac CLI, then live-test via `n8nac test`.

> **Why `disable-model-invocation: true`?** Deploy mutates remote state on the n8n instance (push + activate + production test) and is therefore a side-effecting operation. The plugin's policy is: side-effecting skills must be explicitly invoked by the user (slash command), never auto-triggered by the model. Other invocable skills like `/n8n-autopilot:build-workflow` may auto-trigger from natural-language prompts because they include their own user-confirmation gates at the deploy step. Apply the same `disable-model-invocation: true` flag to any future skill that performs an irreversible remote mutation without an explicit user gate.

## Steps

### 1. Resolve Workflow

- **File path** (e.g., `workflows/create-lead.workflow.ts`) — use directly
- **Workflow name** (e.g., `create lead`) — find matching `.workflow.ts` in `workflows/`

If `$ARGUMENTS` is provided, use it. Otherwise, ask the user.

### 2. Validate Before Push (mandatory)

```bash
npx n8nac skills validate --strict --json workflows/<name>.workflow.ts
```

If validation fails, **stop and report**. Do not push with validation errors.

### 3. Check Sync Status

```bash
npx n8nac list
```

If the workflow shows ARCHIVED, **stop immediately** — archived workflows are read-only. Do not attempt to push. Inform the user: unarchive via n8n UI first, or create a new workflow.

If the workflow shows CONFLICT, resolve first:
```bash
npx n8nac resolve <id> --mode keep-current   # use local version
```

### 4. Push via n8nac

> **description decorator (n8nac 1.7.0+):** `@workflow` accepts an optional `description` field — set it for better discoverability in `n8nac list` and the n8n UI:
> ```typescript
> @workflow({ name: "My Workflow", description: "What it does in one sentence", settings: { ... } })
> ```

> **mcpTrigger check:** Before pushing, if the workflow contains `mcpTrigger`, verify
> that `availableInMCP: true` is set in the `@workflow` settings. The PreToolUse hook
> (`ensure-mcp-trigger-setting.sh`) auto-fixes `false → true` on push, but warns when the
> field is absent — see the warning output and fix the source file if needed.

```bash
npx n8nac push workflows/<name>.workflow.ts
```

### 4b. Verify Remote State

```bash
npx n8nac verify <workflowId>
```
If verification fails, re-push. This catches edge cases where push succeeded but server state diverged.

### 4c. Check Credential Presence

```bash
npx n8nac workflow credential-required <workflowId>
```

- **Exit 0:** all credentials present → proceed to test
- **Exit 1:** credentials missing → report which credentials need to be created, skip live test

### 5. Check Trigger Type + Infer Payload

```bash
npx n8nac test-plan <workflowId> --json
```

Parse the JSON output and extract `triggerType`, `testable`, and `suggestedPayload`.

| Trigger | Testable? | Action |
|---|---|---|
| `webhook`, `chat`, `form` | Yes | proceed to test |
| `schedule`, `manual`, `errorTrigger` | No | skip live test, report to user |

### 6. Live Test (no activation needed)

`n8nac test` uses the **test URL** (`/webhook-test/`) by default — no activation required.

```bash
npx n8nac test <workflowId> --data '<suggestedPayload from step 5>'
```

- **Class A error (exit 0):** missing credentials/model — report to user, do not iterate
- **Class B error (exit 1):** wiring error — fix, re-validate, re-push, re-test

### 7. Production Test (optional, only with --activate flag)

If the user passes `--activate`:
1. Activate workflow via n8nac:
   ```bash
   npx n8nac workflow activate <workflowId>
   ```
2. Production test:
   ```bash
   npx n8nac test <workflowId> --prod --data '<payload>'
   ```
3. On success: workflow stays active
4. On failure: deactivate workflow, report error

### 8. MCP-Access-Notice (manuell für mcpTrigger-Workflows)

Nach erfolgreichem Push: prüfe, ob das Workflow-File `mcpTrigger` enthält:

```bash
grep -l "mcpTrigger\|n8n-nodes-langchain.mcpTrigger" workflows/<name>.workflow.ts
```

**Falls mcpTrigger gefunden:** Zeige prominenten Hinweis:

```
⚠️  MANUAL PUBLISH REQUIRED — mcpTrigger detected

The MCP endpoint will return 404 until the workflow is published.

Open n8n UI:  <n8n_host>/workflow/<workflowId>
Click:        "Publish" button
```

Grund: `n8nac push` schreibt einen neuen Draft — die bisher publizierte Version bleibt stehen, aber der MCP-Endpoint kann 404 liefern, bis manuell re-published wurde. n8nac kann nicht publishen.

## Safety

- **Always validate before pushing**
- **Workflows deploy as inactive** by default — `n8nac test` uses the test URL, no activation needed
- `--activate` + `--prod` tests against the production webhook URL — use with caution
- This skill is `disable-model-invocation: true` — deployment has side effects
