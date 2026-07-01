---
name: build-stack-v2
description: "EXPERIMENTAL deterministic builder for a whole n8n workflow STACK (multiple sub-workflows wired via Execute Workflow), JS-orchestrated. Takes a PRP-style end-to-end use case, decomposes it into sub-workflows along known rules, fixes the handover contracts between them, documents the architecture (mermaid) in one central file, then builds each sub-workflow bottom-up via build-workflow-v2. Two modes: GREENFIELD (new stack) and EXTEND (change an existing one). Decomposition rules, build order (topological), and per-sub-WF gates are JS control flow the model cannot skip. Use for multi-workflow use cases; for a single workflow use build-workflow-v2."
argument-hint: '"<end-to-end use-case / PRP>"  OR  extend "<stack id-or-name>" "<change>"'
user-invocable: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(npx:*), Workflow
---

# Build Stack v2 — JS-Orchestrated Stack Builder

One level up from [`build-workflow-v2`](../build-workflow-v2/SKILL.md): that ships ONE workflow, this
ships a whole **stack** — an orchestrator plus the sub-workflows it calls via Execute Workflow nodes,
with the handover contracts fixed and the architecture documented. The pipeline is a Claude Code
**Workflow JS script** (`stack.workflow.js`); the script body is the control flow, each step a typed
subagent. The per-sub-workflow build reuses `build-workflow-v2`'s `build.workflow.js` / `edit.workflow.js`
verbatim (one `workflow()` hop each), so every sub-workflow gets the same hard gates.

> **Need a plan to feed this?** If the user has only a rough idea, run
> [`/n8n-autopilot:stack-intake`](../stack-intake/SKILL.md) first — a guided interview that produces the
> PRP-style description this skill digests.

## Why a separate stack builder

A single workflow that does everything is a maintenance trap: untestable in parts, OOM-prone, no reuse.
The decomposition rules (single-responsibility leaves, triggers at the edges, fan-out/fan-in, error +
large-data boundaries — from `n8n-orchestration-patterns`) say *when* to split. This skill applies them
**structurally**: the architect decomposes, the contracts are fixed before any code, and the build runs
**bottom-up by topological sort** — a parent is only built after its children exist, because its
Execute Workflow node needs the child's real `workflowId`. A failed child **halts** its dependents
(no building on a broken foundation) and escalates.

## Architecture — roles are extracted

| agentType | Role |
|---|---|
| `n8n-stack-architect` | decompose a PRP into sub-WFs + handover contracts (greenfield) / plan the delta (extend) |
| `n8n-stack-comprehender` | reconstruct the real call-graph from `executeWorkflow` refs in the local mirror (extend) |
| `n8n-author` | (reused) writes the central architecture doc verbatim |
| build-workflow-v2 agents | (reused, one `workflow()` hop per sub-WF) research → author → validate → deploy → test |

## How to run

1. **Detect the mode** from `$ARGUMENTS`:
   - Starts with `extend ` / names an existing stack + a change → **EXTEND**.
   - Otherwise (a use-case description) → **GREENFIELD**.
   - If ambiguous or empty, ask the user (or point them at `/n8n-autopilot:stack-intake`).
   - **Greenfield auto-detect:** before decomposing, the script checks `docs/*.architecture.md` for a
     stack that already covers the use-case. On a match it returns `status: 'needs-decision'` instead
     of rebuilding — relay the `hint` (re-run as EXTEND with the change, or pass `mode: 'greenfield'`
     to force a fresh build). This stops the silent rebuild-over-a-working-stack case.
2. **Resolve the three sub-script paths.** They are siblings of this skill inside the plugin install:
   - `buildScript` = `<plugin>/skills/build-workflow-v2/build.workflow.js`
   - `editScript`  = `<plugin>/skills/build-workflow-v2/edit.workflow.js`
   - `syncScript`  = `<plugin>/skills/mirror-sync/sync.workflow.js`

   Resolve `<plugin>` as the absolute parent of *this* skill dir (`build-stack-v2`). The script has no
   `fs`/`__dirname`, so these MUST be passed in as args — that is by design.
3. **Invoke `stack.workflow.js` via the `Workflow` tool** (`scriptPath` = absolute path to it; it runs in
   the consumer-repo cwd so `npx n8nac workspace status` resolves the pinned project + sync folder):

   **Greenfield:**
   ```
   Workflow({
     scriptPath: "<plugin>/skills/build-stack-v2/stack.workflow.js",
     args: {
       description: "<full end-to-end use-case / PRP>",
       buildScript: "<plugin>/skills/build-workflow-v2/build.workflow.js"
     }
   })
   ```
   **Extend:**
   ```
   Workflow({
     scriptPath: "<plugin>/skills/build-stack-v2/stack.workflow.js",
     args: {
       mode: "extend",
       target: "<stack id or name hint>",
       change: "<what to change>",
       buildScript: "<plugin>/skills/build-workflow-v2/build.workflow.js",
       editScript: "<plugin>/skills/build-workflow-v2/edit.workflow.js",
       syncScript: "<plugin>/skills/mirror-sync/sync.workflow.js"
     }
   })
   ```
4. Render the **Completion Report** from the returned object. Watch live progress with `/workflows`.

## Phases

**Greenfield** (`stack.workflow.js`): Plan (`n8n-stack-architect` decompose → `stackPlan`) → Document
(`docs/<stack>.architecture.md` — contracts + mermaid, composed deterministically in JS) → Build
(topological bottom-up, one `build.workflow.js` hop per sub-WF, children's real ids fed to parents) →
Report (re-write the doc with real `workflowId`s).

**Extend** (`stack.workflow.js`): Mirror (`mirror-sync` so the local call-graph is complete) →
Comprehend (`n8n-stack-comprehender` reconstructs the DAG from `executeWorkflow` refs) → Plan
(`n8n-stack-architect` delta) → Build (new sub-WFs bottom-up via `build.workflow.js`, then changed
sub-WFs / orchestrator rewiring via `edit.workflow.js`) → Report (update the doc).

> **Local-mirror invariant (EXTEND).** The call-graph is reconstructed from *code*, not memory — so the
> repo must mirror the instance first. `stack.workflow.js` runs `mirror-sync` as phase 0; if a referenced
> child has no local file, the comprehender reports `missingLocal` and you should re-run `mirror-sync`.

## Result → Completion Report

The script returns one of:
- `{ status: 'aborted', reason }` — missing input (no description / no change / no buildScript).
- `{ status: 'needs-decision', reason: 'existing-stack', stackSlug, entryWorkflowId, detail, hint }` —
  greenfield was requested but a matching stack already exists locally. Relay the `hint` verbatim; do
  NOT rebuild. Re-run as EXTEND, or pass `mode: 'greenfield'` to force.
- `{ status: 'failed', stage, reason, … }` — a structural failure (dependency cycle in the plan).
- `{ status: 'partial', … attention }` — some sub-WFs built green, a failure halted the rest. Surface
  `attention` + the per-sub-WF list verbatim; offer to fix the failing sub-WF and resume.
- `{ status: 'success', mode, stackSlug, entry, architectureDoc, buildOrder, subWorkflows[], idMap, … }`.

Render success:
```
## Stack {mode === 'extend' ? 'extended' : 'built'} & wired (build-stack-v2)

**Stack:** {stackSlug}   **Entry:** {entry}
**Architecture doc:** {architectureDoc}
**Build order:** {buildOrder.join(' → ')}

| sub-workflow | status | workflowId | url |
|---|---|---|---|
{ each subWorkflows/applied row }

{ if any non-success: "⚠ {attention}" }
{ if missingLocal: "⚠ Mirror gap: <list> — re-run /n8n-autopilot:mirror-sync." }
```
Each sub-workflow's own live-test outcome lives in its `build.workflow.js` result (the stack records
status + id + url; deep test detail is per-sub-WF). Open the architecture doc for the mermaid + contracts.

## Limits

- **Built on `build-workflow-v2`.** It inherits v2's boundary: gates enforce *that* steps run in order,
  not *that* the authored TS is semantically perfect. Per-sub-WF correctness rests on the node-verifier
  fan-out inside each build.
- **`workflow()` nesting is 1 level.** `stack → build/edit/sync` is fine (those use only `agent()`).
  Do not add a `workflow()` call inside build/edit.
- **Mid-run human steps** (a sub-WF with an mcpTrigger needs a UI Publish; non-HTTP triggers need a
  manual run) are handed back per sub-WF, not driven inside the stack run.
- **Experimental, and test-gated** — end-to-end stack runs should only be trusted once
  `build-workflow-v2` (greenfield + edit) is green against the target instance and the `skills:`
  pass-through is verified.
