#!/bin/bash
# enforce-env.sh — PreToolUse(Bash) hard gate for n8n environment safety.
#
# Rule: an n8n session works in exactly ONE env (instance + project). Every
# INSTANCE-touching `npx n8nac` command MUST resolve to an explicit env, via:
#   - the session env var  N8NAC_ENVIRONMENT=<name>   (the normal per-session default), OR
#   - an inline override    N8NAC_ENVIRONMENT=<name> npx n8nac …  , OR
#   - the CLI flag          npx n8nac --env <name> …             (per-call override)
#
# If NONE of these resolve an env, the command would silently hit the GLOBAL
# active env (`env use`) — which is shared/mutable and wrong when multiple
# sessions target different projects. We refuse that, fail-closed.
#
# Local-only n8nac commands (skills/convert/workspace/env/setup/telemetry/update-ai)
# do not touch an instance and are never gated — EXCEPT `env use` / `env pin`,
# which mutate the shared global active env and are blocked unconditionally
# (clobber-guard; bypass N8N_AUTOPILOT_ALLOW_ENV_USE=1).
#
# Called by: hooks/hooks.json PreToolUse (matcher: Bash). Receives the tool input
# (the command string) as $1.

INPUT="$1"
[ -z "$INPUT" ] && INPUT="$CLAUDE_TOOL_INPUT"

# Only care about n8nac invocations.
echo "$INPUT" | grep -qE 'n8nac' || exit 0

# ── Clobber-guard ────────────────────────────────────────────────────────────
# `env use` / `env pin` mutate the machine-GLOBAL active env (shared across all
# shells and Claude sessions). A session that runs it silently re-points every
# OTHER session's un-pinned commands. Block it unconditionally — sessions pin
# via N8NAC_ENVIRONMENT instead. Bypass only for a deliberate, interactive
# machine-default change during setup:
#   N8N_AUTOPILOT_ALLOW_ENV_USE=1 npx n8nac env use <name>
if [ "${N8N_AUTOPILOT_ALLOW_ENV_USE:-}" != "1" ] \
   && echo "$INPUT" | grep -qE 'n8nac[[:space:]]+(env|environment)[[:space:]]+(use|pin)([[:space:]]|$)'; then
  cat >&2 <<'EOF'
[enforce-env] BLOCKED — `env use` / `env pin` mutates the SHARED global active env.

This rewrites the machine-global default env, which every other shell and Claude
session inherits when they have no explicit env. It is the exact operation that
lets sessions clobber each other. Refused.

To target an env in THIS session WITHOUT touching the global, do one of:
  • set the session default:   export N8NAC_ENVIRONMENT=<env-name>
  • inline for one command:     N8NAC_ENVIRONMENT=<env-name> npx n8nac <cmd> …
  • per-call flag:              npx n8nac --env <env-name> <cmd> …

If you REALLY mean to change the machine-wide default (setup only):
  N8N_AUTOPILOT_ALLOW_ENV_USE=1 npx n8nac env use <env-name>
EOF
  exit 2
fi

# Env already resolved? Allow — explicit flag/inline var, or session default.
if echo "$INPUT" | grep -qE '(--env[ =]|N8NAC_ENVIRONMENT=)'; then
  exit 0   # explicit env in the command (flag or inline var)
fi
if [ -n "$N8NAC_ENVIRONMENT" ]; then
  exit 0   # session default env is set — inherited by this command
fi

# No env resolved. Allow only LOCAL/config subcommands (no instance contact).
# Matched at subcommand position (right after `n8nac`) so a `.workflow.ts`
# filename never trips an instance-keyword. Everything else that touches the
# instance (list/find/pull/push/fetch/verify/test/test-plan/resolve/promote/
# execution/credential[s]/workflow) is gated.
LOCAL_SUBCMD='n8nac[[:space:]]+(skills|convert|convert-batch|workspace|env|environment|setup|setup-modes|telemetry|update-ai|mcp|help|--version|-V|--help|-h)([[:space:]]|$)'
if echo "$INPUT" | grep -qE "$LOCAL_SUBCMD"; then
  exit 0
fi

# No env resolved → block.
cat >&2 <<'EOF'
[enforce-env] BLOCKED — n8n environment is ambiguous.

This instance-touching `npx n8nac` command resolves to NO explicit env, so it
would silently use the GLOBAL active env (shared across sessions). Refused.

Pick the env (= instance + project) explicitly, one of:
  • set the session default:   export N8NAC_ENVIRONMENT=<env-name>
  • inline for one command:     N8NAC_ENVIRONMENT=<env-name> npx n8nac <cmd> …
  • per-call flag:              npx n8nac --env <env-name> <cmd> …

List envs + their projects:  npx n8nac env list --json
EOF
exit 2
