---
name: deploy
description: Push a local .workflow.ts to n8n, verify remote state, and live-test (test URL by default; `--activate --prod` runs production test). Side-effecting — only invoked explicitly via `/deploy`.
argument-hint: "<workflow-name>.workflow.ts [--activate] [--prod]"
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash(npx:*), Bash(grep:*)
---

# Deploy Workflow

Push a local `.workflow.ts` to n8n via `n8nac`, verify remote state, run a live test.

> **Why `disable-model-invocation: true`?** Deploy mutates remote state (push, optional activate, optional production test). Plugin policy: side-effecting skills must be explicitly invoked by the user, never auto-triggered by the model. Skills like `/n8n-autopilot:build-workflow` may auto-trigger because they include user-confirmation gates at the deploy step. Apply the same flag to any future skill that performs an irreversible remote mutation without an explicit user gate.

## Steps

### 1. Resolve workflow

- **File path** (e.g., `workflows/create-lead.workflow.ts`) — use directly
- **Workflow name** (e.g., `create lead`) — find matching `.workflow.ts` in `workflows/`

If `$ARGUMENTS` is provided, use it. Otherwise, ask the user.

### 2. Validate before push (mandatory)

```bash
npx n8nac skills validate workflows/<name>.workflow.ts --strict --json
```

If validation fails → **stop and report**. Do not push with validation errors.

### 3. Drift check (mandatory — enforced by push-gate hook)

```bash
# Extract workflow id from @workflow({ id: '...' }) in the file
WF_ID=$(grep -oE "id:[[:space:]]*['\"][A-Za-z0-9]{10,}['\"]" workflows/<name>.workflow.ts | head -1 | grep -oE "[A-Za-z0-9]{10,}")

# Refresh remote cache, then read sync status
npx n8nac fetch "$WF_ID"
npx n8nac list --search "$WF_ID" --json
```

Decision table:

| status | Action |
|---|---|
| `TRACKED` | Safe to push. Proceed to step 4. |
| `LOCAL_ONLY` | New workflow (no remote yet). Safe to push (no overwrite risk). |
| `CONFLICT` / `MODIFIED_BOTH` / `DIVERGED` | **STOP.** Remote was modified since last pull. Run `npx n8nac pull "$WF_ID"`, re-apply your local change on top, then re-validate. NEVER use `npx n8nac resolve --mode keep-current` without explicit user authorization — the push-gate hook will block it. |
| `REMOTE_ONLY` | Local file references a remote id but no local tracking entry. Run `npx n8nac pull "$WF_ID"` first. |
| `ARCHIVED` | Read-only. Stop. Tell the user to unarchive via n8n UI or create a new workflow. |

If the user has confirmed they want to discard the remote change:
```bash
N8N_AUTOPILOT_ALLOW_LOCAL_WINS=1 npx n8nac push workflows/<name>.workflow.ts --verify
```

### 4. Push + verify in one call

> **mcpTrigger check:** If the workflow contains `mcpTrigger`, the PreToolUse hook (`ensure-mcp-trigger-setting.sh`) auto-fixes `availableInMCP: false → true` on push and warns when the field is missing entirely — see the warning and patch the source file if needed.

> **`@workflow` description field (n8nac 1.7.0+):** Set `description` for better discoverability in `n8nac list` + n8n UI:
> ```typescript
> @workflow({ name: "My Workflow", description: "What it does in one sentence", settings: { ... } })
> ```

```bash
npx n8nac push workflows/<name>.workflow.ts --verify
```

`--verify` fetches the workflow after push and validates it against the local schema in one call. If verify fails → re-push.

### 5. Check credential presence

```bash
npx n8nac workflow credential-required <workflowId>
```

- **Exit 0:** all present → proceed to test
- **Exit 1:** credentials missing → report which credentials are needed, skip live test

### 6. Trigger classification + payload inference

```bash
npx n8nac test-plan <workflowId> --json
```

Extract `triggerType`, `testable`, `suggestedPayload`.

| Trigger | Testable via CLI? | Action |
|---|---|---|
| `webhook`, `chat`, `form` | yes | proceed to live test |
| `schedule`, `manual`, `errorTrigger` | no | skip live test, surface manual-execution notice (see step 9) |

### 7. Live test (test URL — no activation needed)

`n8nac test` calls the test URL (`/webhook-test/`) by default.

```bash
npx n8nac test <workflowId> --data '<suggestedPayload from step 6>'
# For GET/HEAD webhooks (workflow reads $json.query):
npx n8nac test <workflowId> --query '<suggestedPayload>'
```

- **Class A error (exit 0):** missing credentials / model → report to user, do not iterate.
- **Class B error (exit 1):** wiring error → fix → re-validate → re-push (`--verify`) → re-test (max 3 cycles).

### 8. Production test (optional, only with `--activate`)

If the user passes `--activate`:

1. Activate the workflow:
   ```bash
   npx n8nac workflow activate <workflowId>
   ```
2. Production test:
   ```bash
   npx n8nac test <workflowId> --prod --data '<payload>'
   ```
3. On success → workflow stays active.
4. On failure → deactivate via `npx n8nac workflow deactivate <workflowId>`, report error.

### 9. mcpTrigger publish notice (manual)

After a successful push, check whether the workflow uses `mcpTrigger`:

```bash
grep -l "mcpTrigger\|n8n-nodes-langchain.mcpTrigger" workflows/<name>.workflow.ts
```

If yes, resolve the user-facing URL via the CLI (do not string-concat `<host>/workflow/<id>`):

```bash
npx n8nac workflow present <workflowId> --json
```

Surface a prominent notice using that URL:

```
⚠️  MANUAL PUBLISH REQUIRED — mcpTrigger detected

The MCP endpoint will return 404 until the workflow is published.

Open n8n UI:  <url from `n8nac workflow present`>
Click:        "Publish" button
```

`n8nac push` writes a new draft. The previously-published version stays live, but its MCP endpoint may diverge from the new draft. Each push to an `mcpTrigger` workflow requires a fresh UI publish — n8nac cannot publish on your behalf.

## Safety

- Always validate before pushing.
- Workflows deploy as inactive by default. `n8nac test` uses the test URL, no activation needed.
- `--activate` + `--prod` tests against the production webhook URL — use with caution.
- `disable-model-invocation: true` — deployment has side effects.
