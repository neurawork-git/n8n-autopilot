---
name: mirror-sync
description: "Pull every remote-only n8n workflow into the local repo so it mirrors the instance, via a deterministic JS Workflow (discover remote-only → fan-out pull → verify). Establishes and refreshes the local-first invariant that /n8n-autopilot:build-workflow-v2's edit flow relies on. Auto-triggered by the SessionStart drift probe (check-mirror-drift.sh) and run as the final step of init-repo."
argument-hint: ""
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash(npx:*), Workflow
---

# Mirror Sync — pull all remote-only workflows

Make the local repo a complete mirror of the instance's workflows. n8nac has no `pull-all`; this skill drives the `list --json` → per-id `pull` loop deterministically via a Workflow script (fan-out, no silent cap, verified).

## Why this exists

The edit flow of `/n8n-autopilot:build-workflow-v2` is **local-first** — it assumes every remote workflow already has a local `.workflow.ts`. Nothing established that invariant before (init pulled *schemas*, never *workflows*). This skill is the enforcement: it pulls the gap and the SessionStart probe keeps it honest.

## How to run

Invoke the script via the `Workflow` tool (runs in the consumer-repo cwd so `npx n8nac` resolves the pinned project + sync folder):

```
Workflow({ scriptPath: "<plugin>/skills/mirror-sync/sync.workflow.js" })
```

Then render the result:
- `{ status:'success', pulled, mirrorComplete:true }` — report how many pulled (0 = already complete).
- `{ status:'partial', failed:[…], remoteOnlyRemaining }` — list the failed ids + reasons; suggest a re-run or a manual `npx n8nac pull <id>`.

Watch live progress with `/workflows`.

## Phases (in the script)

1. **Discover** — `n8n-mirror` runs `npx n8nac list --json` and returns the remote-only set (status matches `/REMOTE/i` — vocabulary-robust across n8nac versions — and not archived). Zero remote-only → returns early, mirror already complete.
2. **Pull** — fan-out: one `n8n-mirror` agent per missing workflow runs `npx n8nac pull <id>`. Failures are collected, not fatal.
3. **Verify** — re-discover; `remoteOnlyRemaining === 0` ⇒ `mirrorComplete`.

## Triggers

| Source | Mechanism |
|---|---|
| SessionStart | `scripts/check-mirror-drift.sh --quiet` emits `AUTOPILOT_ACTION_REQUIRED: /n8n-autopilot:mirror-sync` only when remote-only workflows exist (no blind every-session pull). |
| init-repo | Step 6.5 runs this after schemas, so a fresh repo starts as a full mirror. |
| Manual | `/n8n-autopilot:mirror-sync` any time. |

## Boundaries

- **Workflows only.** Node schemas are a separate concern (`check-schema-versions.sh` → `/n8n-autopilot:pull-schemas`); this skill does not duplicate them.
- **Pull only** — never push/resolve/delete. Archived workflows are skipped (read-only).
- Large instances: fan-out is capped at ~10 concurrent by the Workflow runtime; all queued workflows still complete. The pull list is logged in full — no silent truncation.
