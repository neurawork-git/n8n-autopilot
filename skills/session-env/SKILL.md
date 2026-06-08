---
name: session-env
description: Explain and verify how a Claude session pins itself (and all its n8nac workflow/instance commands) to exactly ONE n8n environment without clobbering other sessions' global active env. Use when the user asks "which env am I on", "how does session env pinning work", "pin this session to env X", "why was my env command blocked", or wants to verify env isolation. Reports the session-resolved env vs the shared global active, and can run the empirical isolation test.
argument-hint: "[test | <env-name>]"
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash(npx:*), Bash(bash:*), Bash(grep:*), Bash(node:*), Bash(test:*)
---

# Session Env Pinning — one session, one env, no cross-session clobber

## The model (why this exists)

n8nac stores a **machine-GLOBAL active environment** (`activeEnvironmentId` in
`~/n8nac-config.json`), set by `n8nac env use <name>` / `env pin`. It is shared by
**every shell and every Claude session** on the machine. If two sessions each run
`env use`, the last one wins and silently re-points the other session's commands at
the wrong instance/project. That is the failure mode we prevent.

**The rule: a session pins itself with the `N8NAC_ENVIRONMENT` env var — never with
`env use`.** Instance-touching n8nac commands honour `N8NAC_ENVIRONMENT` (and the
per-call `--env` flag) and route to that env's instance **without writing the global
active**. So N sessions can target N different envs concurrently, and none disturbs
the others.

### Three ways to resolve an env for a command (all session-scoped, none mutate global)

| Scope | How | When |
|---|---|---|
| Whole session (default) | `.claude/settings.json` → `"env": { "N8NAC_ENVIRONMENT": "<name>" }` | the normal per-repo pin — set once |
| Whole shell | `export N8NAC_ENVIRONMENT=<name>` | ad-hoc terminal work |
| One command | `npx n8nac --env <name> <cmd>` or `N8NAC_ENVIRONMENT=<name> npx n8nac <cmd>` | override for a single call |

`.claude/settings.json` in this repo pins the session via the `env` block — that value
is exported into every Bash tool call, so every n8nac command inherits it.

## Enforcement (two hooks)

- **`scripts/enforce-env.sh`** (PreToolUse / Bash) — fail-closed:
  1. Any **instance-touching** `npx n8nac` command that resolves to **no** env
     (no `--env`, no inline `N8NAC_ENVIRONMENT=`, no session `$N8NAC_ENVIRONMENT`) is
     **BLOCKED** (exit 2) — otherwise it would silently hit the shared global active.
  2. **`env use` / `env pin` are BLOCKED unconditionally** (clobber-guard) — they
     mutate the shared global. Bypass only for a deliberate machine-default change:
     `N8N_AUTOPILOT_ALLOW_ENV_USE=1 npx n8nac env use <name>`.
  3. Local-only subcommands (`skills`, `convert`, `workspace`, `env list/status/...`,
     `setup`, `telemetry`, `update-ai`, `help`) never touch an instance → never gated.
- **`scripts/report-session-env.sh`** (SessionStart) — prints the session's resolved
  env (name + host + project) up front, or warns if it is falling back to the shared
  global active (no session var set).

## Known gotcha — `workspace status` is env-BLIND

`npx n8nac workspace status` always reflects the **global active** env and **ignores**
`N8NAC_ENVIRONMENT` / `--env`. For session-aware resolution use **`env status`** or
**`env list --json`** filtered by `N8NAC_ENVIRONMENT`. Routing of actual instance
calls (`pull`/`push`/`list --remote`/…) DOES honour the session var — only the
`workspace status` *reporter* is blind. (Empirically confirmed; see the test below.)

## Verify it (this session)

```bash
# Which env does THIS session actually target (honours N8NAC_ENVIRONMENT)?
npx n8nac env status --json

# What is the shared global active (what un-pinned sessions get)?
npx n8nac env list --json | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{const j=JSON.parse(d.slice(d.indexOf('{')));console.log('global active:',j.activeEnvironmentId)})"
```

If `env status` resolves a *different* env than the global active, the pin is working
exactly as intended — your session is isolated.

## Extensive isolation test

`scripts/test-env-isolation.sh` is the empirical proof harness. It is **read-only**
against instances, **never** runs `env use` (the clobber op under test), captures the
global active at start, and re-asserts it is unchanged at the end. It checks:

1. `N8NAC_ENVIRONMENT` routes each env to its own host.
2. `--env` flag routes identically, independent of any session var.
3. **SAFETY** — global active is untouched by session-scoped resolution.
4. `workspace status` env-blindness (documents the gotcha).
5. The gate blocks no-env instance commands, allows resolved/local ones.
6. The clobber-guard blocks `env use` / `env pin` but still allows `env list` / `env status`.

```bash
bash scripts/test-env-isolation.sh
# or pick the two envs explicitly:
ENV_A=dev ENV_B=prod bash scripts/test-env-isolation.sh
```

Expected: `=== 17 passed, 0 failed ===` and `SAFETY OK: global active unchanged`.

## Propagation into Claude Workflows (build-workflow-v2 / build-stack-v2)

The v2 pipelines are JS Workflows that spawn `agent()` subagents (`n8n-researcher`,
`n8n-author`, `n8n-validator`, `n8n-deployer`, `n8n-tester`). Their scripts pass **no**
`--env`; the agent defs say *"env is inherited, run every n8nac command bare."* That
relies on `N8NAC_ENVIRONMENT` propagating **session → Workflow runtime → subagent Bash**.

**Verified (5.0.0):** a probe Workflow (a generic agent AND the real `n8n-tester`
agentType) both saw `N8NAC_ENVIRONMENT`, resolved the session env + host via
`env status --json`, and ran a bare instance command against the correct instance —
leaving the global active untouched. So the inherited-bare model is correct: do **not**
add `--env` inside pipeline agents, and never set the session pin via `env use`. If a
future session sets no `N8NAC_ENVIRONMENT`, subagents inherit none either → bare instance
commands are gated/ambiguous, exactly as in the main session (fail-closed, not silent).

## Quick answers

- **"Which env am I on?"** → `npx n8nac env status --json` (session-aware).
- **"Pin this session to X"** → add `"N8NAC_ENVIRONMENT": "X"` to `.claude/settings.json`
  `env` block (NOT `env use X`). Verify with `env status --json`.
- **"My command was blocked"** → either no env resolved (set `N8NAC_ENVIRONMENT` or pass
  `--env`), or you ran `env use`/`env pin` (use the session var instead; bypass only for
  a real machine-default change).
- **"Switch the machine default for everyone"** → that is `env use`, intentionally
  guarded: `N8N_AUTOPILOT_ALLOW_ENV_USE=1 npx n8nac env use <name>`.
