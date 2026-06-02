---
name: test-manual
description: Test a non-HTTP-trigger workflow (schedule, manual, errorTrigger) that n8nac cannot fire from the CLI. Resolves the n8n UI URL, waits for you to run it and report the execution-id, then inspects the run. Read-only against the instance.
argument-hint: "<workflowId>"
user-invocable: true
allowed-tools: Read, Bash(npx:*)
---

# Test a Non-HTTP-Trigger Workflow

`npx n8nac test` can only fire **webhook / chat / form** triggers. For `schedule`, `manual`, and
`errorTrigger` workflows the run must be started in the n8n UI. This skill packages that detour into
one flow so you do not have to hand-assemble the URL and the `execution get` command each time.

> Why this exists: non-HTTP manual-test detours were the single most frequent friction observed in
> real production runs.

## Steps

### 1. Resolve the workflow id

Use `$ARGUMENTS` as the workflow id. If empty, ask the user (or extract it from the `.workflow.ts`
they name: `grep -oE "id:[[:space:]]*['\"][A-Za-z0-9]{10,}['\"]" <file> | head -1`).

### 2. Confirm it really is a non-HTTP trigger

```bash
npx n8nac test-plan <workflowId> --json
```

- If `triggerType` is `webhook` / `chat` / `form` (i.e. `testable: true`) → STOP and tell the user
  to use `npx n8nac test <workflowId>` (or `/n8n-autopilot:deploy`) instead — no manual step needed.
- If `schedule` / `manual` / `errorTrigger` → continue.

### 3. Resolve the UI URL (never string-concat the host)

```bash
npx n8nac workflow present <workflowId> --json
```

Surface a clear instruction to the user with the URL from the output:

```
▶  MANUAL EXECUTION REQUIRED — <triggerType> trigger (n8nac cannot fire it)

Open n8n UI:  <url from `n8nac workflow present`>
Click:        "Execute Workflow"
Then paste the execution-id here (top of the execution, or from the URL).
```

### 4. Wait for the execution-id

Stop and wait for the user to report the `execution-id`. Do not fabricate one.

### 5. Inspect the run

```bash
npx n8nac execution get <executionId> --include-data
```

Read the output and report: success/failure, which node failed (if any), and the relevant
output/error data. If it failed on a wiring error, hand back to `/n8n-autopilot:deploy`'s fix loop.

## Notes

- Read-only against the instance — this skill only resolves URLs and reads execution data. The
  actual run is started by the user in the UI.
- If the user reports no execution-id (the run did not start), re-check the URL and that the user
  clicked "Execute Workflow" (not "Save").
