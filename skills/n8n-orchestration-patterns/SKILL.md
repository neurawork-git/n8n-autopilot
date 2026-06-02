---
name: n8n-orchestration-patterns
description: Fan-out / fan-in, parallel sub-workflow execution, and batch-orchestrator patterns in n8n. Use when a workflow processes a LIST in parallel, calls sub-workflows, needs faster wall-clock on many items, has a webhook that would otherwise block for minutes, or asks "how do I run sub-workflows in parallel / fan out / fan in".
user-invocable: false
---

# n8n Orchestration Patterns (fan-out / fan-in / batch)

Battle-tested against the n8n docs (main) and real production workflows. The naive approach
(branch-split) does NOT parallelize under the modern default — read the trap first.

---

## The trap: branch-split alone does NOT parallelize

| Mechanic | Behaviour |
|---|---|
| `executeWorkflow` `mode: each` | runs **sequentially**, one input item at a time |
| `executeWorkflow` `mode: once` | all items in one sub-workflow call |
| Workflow `executionOrder: 'v1'` (default ≥ 1.0) | **completes one branch before starting the next** |
| Workflow `executionOrder: 'v0'` (legacy) | first node of *every* branch, then second node of every branch — layer-by-layer, all branches interleaved |
| `N8N_CONCURRENCY_PRODUCTION_LIMIT` | does **NOT** apply to sub-workflow executions |

So: 5 branches each `[Filter → executeWorkflow]` under `executionOrder: 'v1'` run **serially** —
wall-clock = sum of all branches = no speedup. `executeWorkflow mode: each` is sequential per item.

---

## Pattern A — `executionOrder: 'v0'` + branch-split (regular mode, no queue)

Layer-by-layer scheduling means when branch 0's `executeWorkflow` awaits (e.g. an LLM call), the
engine schedules branch 1's, then 2,3,4 → all sub-workflow calls are in-flight at once (Node async I/O).

```typescript
@workflow({
  name: 'Parallel Orchestrator',
  settings: {
    executionOrder: 'v0',     // ← CRITICAL — without this, branches run serially
    executionTimeout: 7200,
  },
})
```
Shape: a Code node assigns `bucket: idx % N` → N `Filter` nodes split by bucket → N `executeWorkflow`
nodes → `Merge` (`mode: append`, `numberInputs: N`). Speedup ≈ N branches.
> Caveat: v0 interleaving was less aggressive than expected for some (n8n issue #13620, closed
> "not planned"). On production-critical paths: **measure, don't assume.** Guaranteed N× only via queue mode.

## Pattern B — Wait=OFF + DataTable fan-in  ← RECOMMENDED

Cleaner than a resumeUrl callback: no webhook between workflows (org veto), no HMAC-signature pain,
and a persistent audit trail. See `n8n-autopilot:data-tables` for the table CRUD.

1. **Parent** generates a `batch_id` per run, counts `N` = list length.
2. **Fan-out** — one `executeWorkflow` node, `mode: each` + **`Wait for Sub-Workflow Completion: false`**.
   Fires all sub-workflows async, no return. Pass `batch_id` + `item_idx` to each.
3. **Each sub-workflow** ends by writing a DataTable row: `batch_id`, `item_idx`, `status`, `result`.
4. **Fan-in** — Parent: a `Wait` node + loop polls `COUNT(*) WHERE batch_id = X` until `>= N` (or timeout),
   then reads the rows and merges.

**Error-state (critical):** without an error row the parent polls forever. Do **NOT** use
`continueOnFail: true` (masks silent failures — vetoed). Instead set the risky node's
**"On Error" → "Continue (using error output)"** and route the error output to a DataTable write
(`status: 'error'`, error text). Count still reaches N; the failure is logged and visible.

**Gotchas:**
- Sub-workflow retry → duplicate row: **upsert** on `(batch_id, item_idx)`, not insert — see
  `n8n-autopilot:data-tables` for the exact upsert shape (filters.conditions + matchingColumns).
- Poll loop vs `EXECUTIONS_TIMEOUT`: add a max-iterations guard + a timeout branch that returns partial results.
- 100 items = 100 concurrent executions; `N8N_CONCURRENCY_PRODUCTION_LIMIT` does NOT cap sub-workflows
  → cap via queue-mode worker `--concurrency` instead.
- Count-query race: DataTable insert is atomic per row, append-only count is safe — no lock needed.

## Pattern B2 — official resumeUrl fan-out/fan-in (veto grey zone)

n8n's official answer (templates [2536](https://n8n.io/workflows/2536-pattern-for-parallel-sub-workflow-execution-followed-by-wait-for-all-loop/),
[6247](https://n8n.io/workflows/6247-optimize-speed-critical-workflows-using-parallel-processing-fan-outfan-in/)).
`executeWorkflow Wait=false` + pass `$execution.resumeUrl` (+ unique suffix per item); parent pauses
at a `Wait` node (`resume: On Webhook Call`); sub-workflow HTTP-POSTs the result to the resumeUrl →
instant resume instead of polling. Cost: it IS a webhook child→parent (collides with "no webhook
between workflows") and carries HMAC-signature pain. Use only if that veto is lifted for the case.

## Pattern C — Queue mode (true parallelism, infra change)

`EXECUTIONS_MODE=queue` + ≥1 worker with `--concurrency=10` (Redis + worker pods). Sub-workflow calls
become queue jobs, processed in parallel. The only guaranteed N× speedup. Self-hosted/k8s: set via Helm values.

---

## Synchronous batch + fast-return webhook

When a webhook triggers heavy batch work, do NOT let the webhook connection block for minutes
(a real batch orchestrator once blocked **41 min**). Two valid shapes:

- **Fast-return**: webhook immediately responds `202 { batch_id }` via `respondToWebhook`, then the
  batch runs detached; the caller polls a status endpoint / DataTable by `batch_id`.
- **Synchronous batch orchestrator**: when the item count is bounded and fits inside
  `EXECUTIONS_TIMEOUT`, a single synchronous orchestrator (no queue/worker) is *simpler* and was
  chosen over an async queue/worker split in EV-Workflows once the queue's complexity outweighed its
  benefit. Pick the simplest shape that fits the timeout — don't add a queue you don't need.

---

## Anti-patterns

- ❌ Branch-split with `executionOrder: 'v1'` — serial, zero speedup.
- ❌ Treating `executeWorkflow mode: each` as "parallel per item" — docs say sequential.
- ❌ Webhook-trigger sub-workflow (or HTTP node hitting `/webhook/…`) between your own workflows — org veto.
- ❌ `continueOnFail: true` to "keep the batch going" — masks silent failures; use the error-output branch.
