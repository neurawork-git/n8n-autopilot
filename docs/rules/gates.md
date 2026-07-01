# Hook Gates — Push-Gate & Env-Gate

Full mechanism + rationale for the two `PreToolUse` hooks. CLAUDE.md carries the
one-line summary; this is the load-bearing detail.

---

## Push-Gate (drift protection — `scripts/push-gate.sh`)

The `PreToolUse` hook blocks two operations by default:

1. **`npx n8nac push <file>`** when `npx n8nac list --search <id>` reports status
   `CONFLICT`, `MODIFIED_BOTH`, `DIVERGED`, or `REMOTE_ONLY` — i.e. remote has changed
   since the last local fetch.
2. **`npx n8nac resolve <id> --mode keep-current|keep-local|local-wins`** — always
   blocked, because it overwrites remote with local in one step.

Bypass (single command, only after explicit user authorization that the remote change
should be discarded):

```bash
N8N_AUTOPILOT_ALLOW_LOCAL_WINS=1 <re-run the n8nac command>
```

Default reconciliation path when push is blocked:
1. `npx n8nac pull <id>` — remote wins, sync local
2. Re-edit the local file with your intended change
3. `npx n8nac push <id> --verify` again

The hook auto-runs `npx n8nac fetch <id>` before judging status, so the verdict is always
against fresh remote state. Workflows without an `id:` field (new creations) are never blocked.

---

## Env-Gate (one env per session — `scripts/enforce-env.sh`)

A session works in exactly ONE n8n env (instance + project). The `PreToolUse` hook
**fail-closed BLOCKS** any instance-touching `npx n8nac` command that resolves to NO explicit
env — otherwise it would silently hit the mutable GLOBAL active env (`env use`), which is shared
across sessions and wrong when sessions target different projects.

An env is "resolved" (command allowed) when ANY of these holds:
- session default set: `export N8NAC_ENVIRONMENT=<env-name>` (the normal per-session pin), or
- inline: `N8NAC_ENVIRONMENT=<env-name> npx n8nac …`, or
- per-call flag: `npx n8nac --env <env-name> …`.

Local-only subcommands never touch an instance and are never gated:
`skills`, `convert`, `convert-batch`, `workspace`, `env`, `setup`, `setup-modes`, `telemetry`,
`update-ai`, `help`, `--version`. Everything that contacts the instance (`list`, `find`, `pull`,
`push`, `fetch`, `verify`, `test`, `test-plan`, `resolve`, `promote`, `execution`, `credential[s]`,
`workflow`) is gated.

`npx n8nac env list --json` lists envs + their projects. n8nac itself throws
`Unknown workspace environment: <name>` on a bogus env name (so a typo fails closed, never silently
falls back). The SessionStart hook `scripts/report-session-env.sh` prints the active session env
(name + host + project) so you always know where you are. **Verified routing**: `N8NAC_ENVIRONMENT`
and `--env` both route instance commands to the named env's instance, independent of the global active.

**Clobber-guard:** `enforce-env.sh` also **blocks `env use` / `env pin` unconditionally** — those
mutate the machine-GLOBAL active env (shared across all sessions) and are the exact operation that
lets one session re-point another's un-pinned commands. Sessions pin via `N8NAC_ENVIRONMENT`, never
`env use`. Bypass for a deliberate machine-default change only: `N8N_AUTOPILOT_ALLOW_ENV_USE=1 npx
n8nac env use <name>`. **Gotcha:** `workspace status` is env-blind (reflects the global active, ignores
the session var) — use `env status` / `env list --json` for session-aware resolution.

Full model + empirical isolation test (`scripts/test-env-isolation.sh`, 17 assertions):
**[`session-env`](../../skills/session-env/SKILL.md)** (`/n8n-autopilot:session-env`).
