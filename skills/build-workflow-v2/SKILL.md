---
name: build-workflow-v2
description: "EXPERIMENTAL deterministic variant of build-workflow + deploy, JS-orchestrated. Two modes: GREENFIELD (new workflow) and EDIT (change an existing one). Phase ordering, gate-checks (validate / drift-safe push --verify), and fix-loop limits are enforced by a Claude Code JS Workflow script instead of prose — gates become if/while control flow the model cannot skip or short-circuit. Subagent roles live in agents/n8n-*.md. Use when you want hard-enforced discipline over the soft prose pipelines."
argument-hint: '"<new workflow description>"  OR  edit "<id-or-name>" "<change>"'
user-invocable: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(npx:*), Workflow
---

# Build Workflow v2 — JS-Orchestrated (deterministic gates)

Same outcome as [`build-workflow`](../build-workflow/SKILL.md) + [`deploy`](../deploy/SKILL.md): ship a verified live execution on n8n. **Difference:** the pipeline is a Claude Code **Workflow JS script**, not prose. The script body is the control flow; each step is a small typed subagent (`agents/n8n-*.md`) that runs the real `npx n8nac …` command and returns structured output.

## Why v2

Prose pipelines are soft — the model is *told* to validate before push, *told* "max 3 cycles", *told* never claim a fix before inspecting the execution. v2 makes those structural:

| Soft (prose v1) | Hard (v2 JS) |
|---|---|
| "validate, then push" | `if (!validate.passed) { fix-loop }` — push unreachable until passed |
| "max 3 fix cycles" | `while (cycle <= 3)` — a real counter |
| "ALWAYS test after push" | Test phase only reachable after `push.verified === true` |
| "Push ≠ Fix" | `status:'success'` only returned after the execution is inspected — no other path emits it |

**Boundary:** the script enforces *that* gates run in order and loops are bounded — not *that* the authored TS is correct. The `n8n-node-verifier` fan-out guards correctness (kills the #1 runtime killer: a guessed param key n8n silently ignores).

## Architecture — roles are extracted, not inline

The orchestrator scripts hold **only** control flow + schemas + one-line tasks. Every subagent's role, CLI rules, tools, and model live in a reusable agent definition:

| agentType | Role | Tools |
|---|---|---|
| `n8n-researcher` | plan: sync folder, template lookup, node discovery, trigger, test data | read + Bash |
| `n8n-node-verifier` | adversarial param contract for one node type | read + Bash |
| `n8n-comprehender` | pull/read existing workflow, summarize shape + change site (EDIT) | read + Bash |
| `n8n-author` | write / edit / fix the `.workflow.ts` | read/write + Bash |
| `n8n-validator` | `validate --strict --json` gate | read + Bash |
| `workflow-reviewer` | design-quality gate (HTTP-in-Code, masked errors, AI sub-node miswiring) the validator can't catch | read + Bash |
| `n8n-deployer` | drift-aware `push --verify` gate | read + Bash |
| `n8n-tester` | test-plan classify, credential check, live test, execution inspect | read + Bash |

Both scripts and both modes reuse the same agents — change a role once, both flows get it.

## How to run

1. **Detect the mode** from `$ARGUMENTS`:
   - Starts with `edit ` / names an existing workflow id or name + a change → **EDIT**.
   - Otherwise (a description of something new) → **GREENFIELD**.
   - If ambiguous or empty, ask the user.
2. **Invoke the matching script via the `Workflow` tool** (`scriptPath` = absolute path to the script in this skill dir; it runs in the consumer-repo cwd so `npx n8nac workspace status` resolves the pinned project + sync folder):

   **Greenfield:**
   ```
   Workflow({
     scriptPath: "<plugin>/skills/build-workflow-v2/build.workflow.js",
     args: { description: "<full new-workflow description>", testData: "<explicit JSON payload or empty>" }
   })
   ```
   **Edit:**
   ```
   Workflow({
     scriptPath: "<plugin>/skills/build-workflow-v2/edit.workflow.js",
     args: { target: "<workflow id or name>", change: "<what to change>", testData: "<optional>" }
   })
   ```
3. Render the **Completion Report** from the returned object. Do not re-run the n8nac commands yourself — the workflow's agents already did. Watch live progress with `/workflows`.

## Phases

**Greenfield** (`build.workflow.js`): Research (plan + per-node param fan-out) → Author → Validate gate (≤3) → Review gate (≤2, design-quality blockers) → Deploy gate (`push --verify`) → Test (Path A live-test loop / Path B handoff).

**Edit** (`edit.workflow.js`): Comprehend (local-first; refresh to remote base, summarize change site) → Verify new node types → Patch (preserve the rest, keep the id) → Validate gate (≤3) → Review gate (≤2, design-quality blockers, change-site only) → Deploy gate (drift-safe) → Test.

> **Local-mirror invariant (EDIT).** The repo is expected to mirror remote workflows locally (pulls enforced). The edit flow is therefore **local-first**: `n8n-comprehender` prefers the local file and only pulls to reach remote base if the file is stale/missing (and flags it). Because it refreshes to remote base *before* patching, a push-time conflict only happens if remote changed *during* the run — in which case the deploy gate fails cleanly (no clobber) and asks for a re-run.

## Result → Completion Report

The scripts return one of:
- `{ status: 'aborted', reason }` — missing input.
- `{ status: 'failed', stage, … }` — a gate failed (validate after 3 cycles / review after 2 cycles with unresolved `blockers` / deploy drift). Surface stage + errors/blockers + any `hint` verbatim, offer next step.
- `{ status: 'success', mode, workflowId, filePath, url, triggerType, hasMcpTrigger, validateCycles, reviewWarnings, test, … }`. Surface `reviewWarnings` (advisory, non-blocking) if present.

Render success:
```
## Workflow {mode === 'edit' ? 'edited' : 'deployed'} & verified (v2 / JS-orchestrated)

**ID:** {workflowId}   **URL:** {url}   **File:** {filePath}
**Trigger:** {triggerType}{ mcp note if hasMcpTrigger }
**Gates:** validate passed (cycles: {validateCycles}) · review passed{ if reviewWarnings: ` (${reviewWarnings.length} warning(s))` } · push --verify ✓{ edit: · localMirrorHeld / refreshed }
{ if missingSchemas: "⚠ Missing schemas: <list> — /n8n-autopilot:pull-schemas" }
{ if credentialsMissing: "⚠ Class-A credentials missing: <list> (informational)" }

**Live test:** outcome={test.outcome} · exec={test.executionId} ({test.executionStatus})
output: {test.outputSample}
{ if test.outcome=='manual-required': "⚠ Non-HTTP trigger — open {test.presentUrl}, run it, then /n8n-autopilot:test-manual {workflowId}." }
{ if hasMcpTrigger: "⚠ MCP endpoint 404 until you Publish in the UI." }
```

## Limits

- **Mid-run human steps** (Path B/D Execute/Publish) are handed back, not driven inside the workflow (a background workflow can't prompt).
- The script body has **no shell/fs** — every n8nac call is one `agent()` hop running Bash. Determinism lives in the JS branching, not the command execution.
- **Experimental.** `build-workflow` (v1) + `deploy` remain the supported default until v2 is field-tested.
