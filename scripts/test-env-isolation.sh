#!/usr/bin/env bash
# test-env-isolation.sh — Empirical proof that per-session env pinning
# (N8NAC_ENVIRONMENT / --env) routes instance commands correctly AND never
# mutates the shared GLOBAL active env, so concurrent Claude sessions cannot
# clobber each other.
#
# READ-ONLY against instances. NEVER runs `env use` / `env pin` (that is the
# clobber operation under test). Captures the global active at start and
# re-asserts it is unchanged at the end.
#
# Usage:
#   bash scripts/test-env-isolation.sh                 # uses two auto-picked envs
#   ENV_A=dev ENV_B=prod bash scripts/test-env-isolation.sh
#
# Exit 0 = all assertions pass. Exit 1 = a safety/routing assertion failed.

set -uo pipefail
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$PLUGIN_ROOT/scripts/enforce-env.sh"

PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

jget() { node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{const j=JSON.parse(d.slice(d.indexOf('{')));process.stdout.write(String($1));}catch(e){process.stdout.write('');}})"; }

# ── Resolve host for an env WITHOUT touching global: env status --json honours
#    N8NAC_ENVIRONMENT. Returns the resolved instance host (or empty).
env_host() {
  local name="$1"
  N8NAC_ENVIRONMENT="$name" npx --yes n8nac env status --json 2>/dev/null \
    | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{const j=JSON.parse(d.slice(d.indexOf('{')));const r=j.resolved||j;process.stdout.write(r.host||(r.instance&&r.instance.url)||(r.environmentTarget&&r.environmentTarget.url)||'');}catch(e){process.stdout.write('');}})"
}

global_active() {
  npx --yes n8nac env list --json 2>/dev/null | jget "j.activeEnvironmentId"
}

# ── Gate probe: feed a command string to enforce-env.sh, echo its exit code.
#    Run in a clean env (strip any inherited N8NAC_ENVIRONMENT) unless arg 2 set.
gate_exit() {
  local cmd="$1"; local with_session="${2:-}"
  if [ -n "$with_session" ]; then
    N8NAC_ENVIRONMENT="$with_session" bash "$GATE" "$cmd" >/dev/null 2>&1
  else
    env -u N8NAC_ENVIRONMENT bash "$GATE" "$cmd" >/dev/null 2>&1
  fi
  echo $?
}

echo "=== n8n env-isolation test ==="

# ── Pick two distinct envs with distinct hosts ───────────────────────────────
ENV_A="${ENV_A:-}"; ENV_B="${ENV_B:-}"
if [ -z "$ENV_A" ] || [ -z "$ENV_B" ]; then
  mapfile -t NAMES < <(npx --yes n8nac env list --json 2>/dev/null \
    | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{const j=JSON.parse(d.slice(d.indexOf('{')));(j.environments||[]).forEach(e=>console.log(e.name));})")
  ENV_A="${ENV_A:-${NAMES[0]:-}}"
  # pick a second env whose host differs from ENV_A
  HA="$(env_host "$ENV_A")"
  for n in "${NAMES[@]}"; do
    [ "$n" = "$ENV_A" ] && continue
    if [ "$(env_host "$n")" != "$HA" ] && [ -n "$(env_host "$n")" ]; then ENV_B="$n"; break; fi
  done
fi
[ -z "$ENV_B" ] && ENV_B="${NAMES[1]:-}"
echo "ENV_A=$ENV_A  ENV_B=$ENV_B"

BASE_GLOBAL="$(global_active)"
echo "baseline global active = $BASE_GLOBAL"
echo ""

HA="$(env_host "$ENV_A")"; HB="$(env_host "$ENV_B")"

# ── 1. Routing: N8NAC_ENVIRONMENT resolves each env's own host ────────────────
echo "[1] Session-var routing (env status honours N8NAC_ENVIRONMENT)"
[ -n "$HA" ] && ok "ENV_A '$ENV_A' resolves host: $HA" || bad "ENV_A '$ENV_A' resolved no host"
[ -n "$HB" ] && ok "ENV_B '$ENV_B' resolves host: $HB" || bad "ENV_B '$ENV_B' resolved no host"
[ -n "$HA" ] && [ "$HA" != "$HB" ] && ok "the two envs route to DIFFERENT hosts" || bad "envs resolve to same/empty host — pick distinct envs"

# ── 2. Routing via --env flag (independent of any session var) ───────────────
echo "[2] Per-call --env flag routing"
FA="$(env -u N8NAC_ENVIRONMENT npx --yes n8nac --env "$ENV_A" env status --json 2>/dev/null | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{const j=JSON.parse(d.slice(d.indexOf('{')));const r=j.resolved||j;process.stdout.write(r.host||(r.instance&&r.instance.url)||'');}catch(e){process.stdout.write('');}})")"
[ "$FA" = "$HA" ] && ok "--env $ENV_A resolves same host as session-var ($FA)" || bad "--env routing mismatch: flag=$FA vs var=$HA"

# ── 3. SAFETY: global active unchanged after session-scoped resolution ────────
echo "[3] SAFETY — global active must be untouched by session pins"
NOW_GLOBAL="$(global_active)"
[ "$NOW_GLOBAL" = "$BASE_GLOBAL" ] && ok "global active still '$BASE_GLOBAL' (no clobber)" || bad "GLOBAL MUTATED: $BASE_GLOBAL -> $NOW_GLOBAL"

# ── 4. workspace status is env-BLIND (documents the known gotcha) ─────────────
echo "[4] workspace status env-blindness (must reflect GLOBAL, ignore session var)"
WS_ID="$(N8NAC_ENVIRONMENT="$ENV_B" npx --yes n8nac workspace status --json 2>/dev/null | jget "j.activeEnvironmentId")"
[ "$WS_ID" = "$BASE_GLOBAL" ] && ok "workspace status shows global '$WS_ID' despite N8NAC_ENVIRONMENT=$ENV_B (use env status for session-aware)" || echo "  NOTE: workspace status returned '$WS_ID' (expected global $BASE_GLOBAL) — behaviour may have changed"

# ── 5. Gate: instance command with NO env is BLOCKED ─────────────────────────
echo "[5] enforce-env gate"
[ "$(gate_exit 'npx n8nac list --remote')" = "2" ]            && ok "no-env 'list' BLOCKED (exit 2)"        || bad "no-env 'list' not blocked"
[ "$(gate_exit 'npx n8nac pull abc123')" = "2" ]              && ok "no-env 'pull' BLOCKED (exit 2)"        || bad "no-env 'pull' not blocked"
[ "$(gate_exit "npx n8nac --env $ENV_A list")" = "0" ]        && ok "--env 'list' ALLOWED (exit 0)"         || bad "--env 'list' wrongly blocked"
[ "$(gate_exit "N8NAC_ENVIRONMENT=$ENV_A npx n8nac list")" = "0" ] && ok "inline-var 'list' ALLOWED"        || bad "inline-var 'list' wrongly blocked"
[ "$(gate_exit 'npx n8nac list' "$ENV_A")" = "0" ]            && ok "session-var 'list' ALLOWED"            || bad "session-var 'list' wrongly blocked"
[ "$(gate_exit 'npx n8nac skills validate x.ts')" = "0" ]     && ok "no-env local 'skills' ALLOWED"         || bad "local 'skills' wrongly blocked"
[ "$(gate_exit 'npx n8nac workspace status --json')" = "0" ]  && ok "no-env local 'workspace status' ALLOWED" || bad "local 'workspace' wrongly blocked"

# ── 6. Gate: the CLOBBER operation `env use` / `env pin` must be BLOCKED ──────
echo "[6] clobber-guard — 'env use' / 'env pin' must be BLOCKED (mutates shared global)"
[ "$(gate_exit 'npx n8nac env use prod')" = "2" ]   && ok "'env use prod' BLOCKED"   || bad "'env use prod' NOT blocked (clobber hole open)"
[ "$(gate_exit 'npx n8nac env pin dev')" = "2" ]    && ok "'env pin dev' BLOCKED"    || bad "'env pin dev' NOT blocked (clobber hole open)"
[ "$(gate_exit 'npx n8nac env list --json')" = "0" ] && ok "'env list' still ALLOWED (read-only)" || bad "'env list' wrongly blocked"
[ "$(gate_exit 'npx n8nac env status')" = "0" ]      && ok "'env status' still ALLOWED (read-only)" || bad "'env status' wrongly blocked"

# ── Final safety re-assert ────────────────────────────────────────────────────
echo ""
FINAL_GLOBAL="$(global_active)"
[ "$FINAL_GLOBAL" = "$BASE_GLOBAL" ] && echo "SAFETY OK: global active unchanged ($FINAL_GLOBAL)" || { echo "SAFETY FAIL: global drifted $BASE_GLOBAL -> $FINAL_GLOBAL"; FAIL=$((FAIL+1)); }

echo ""
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
