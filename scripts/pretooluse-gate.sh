#!/usr/bin/env bash
# pretooluse-gate.sh — the ONE PreToolUse entry point for Bash AND PowerShell tool calls.
#
# Claude Code hands a hook its input as JSON on STDIN:
#   {"tool_name":"Bash"|"PowerShell","tool_input":{"command":"…"},"cwd":"…",…}
# There is no CLAUDE_TOOL_INPUT environment variable. Until 5.6.0 every gate read
# `$CLAUDE_TOOL_INPUT`, got an empty string and exited 0 — measured over 120 days of customer
# sessions: dozens of `n8nac push` calls, not one gate ever fired. This script reads stdin once,
# extracts the command, and runs the gates in order. Any gate exiting 2 blocks the tool call.
#
# Gates (each keeps its own script, each takes the command string as $1):
#   1. curl-block        — no direct n8n REST calls (carve-out: /api/v1/data-tables)
#   2. enforce-env.sh    — one env per session, no `env use`
#   3. push-gate.sh      — no push over remote drift
#   4. push-lint-gate.sh — node types/versions on the instance + design-quality lint
#   5. ensure-mcp-trigger-setting.sh — availableInMCP for mcpTrigger workflows (never blocks)
#
# Self-test: bash scripts/test-pretooluse-gate.sh
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RAW="$(cat 2>/dev/null || true)"
# Fast path: this hook runs before EVERY shell call in every session. A call that mentions neither
# n8nac nor an n8n API cannot trip any gate below — leave without spawning node.
if [ -n "$RAW" ]; then
  case "$RAW" in
    *n8nac*|*/api/v1*|*n8n.cloud*|*n8n.io*) ;;
    *) exit 0 ;;
  esac
fi
CMD=""
if [ -n "$RAW" ]; then
  CMD="$(printf '%s' "$RAW" | node -e '
let d=""; process.stdin.on("data",c=>d+=c).on("end",()=>{
  try { const j=JSON.parse(d); const ti=j.tool_input||{}; process.stdout.write(String(ti.command||"")); }
  catch(e) { process.stdout.write(""); }
});' 2>/dev/null || true)"
fi
# Fallbacks: legacy env var, or an explicit argument (self-tests call the gate that way).
[ -z "$CMD" ] && CMD="${CLAUDE_TOOL_INPUT:-}"
[ -z "$CMD" ] && CMD="${1:-}"
[ -z "$CMD" ] && exit 0

# ── 0. the first n8nac command switches the session's n8n mode on (scripts/lib/n8n-mode.sh), so the
#       feedback hooks see this session as n8n work. Never blocks.
. "$HERE/lib/n8n-mode.sh"
if [ -n "$RAW" ] && n8n_mode_is_n8nac_call "$CMD"; then
  SID="$(printf '%s' "$RAW" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
  if [ "${N8N_AUTOPILOT_MODE:-}" != "off" ] && ! n8n_mode_active "$SID"; then
    n8n_mode_enable "$SID" auto || true
  fi
fi

# ── 1. curl-block — direct REST calls against the n8n API bypass every gate below.
if printf '%s' "$CMD" | grep -qE '(curl|wget|urllib|Invoke-RestMethod|Invoke-WebRequest|requests\.|fetch\().*(/api/v1|n8n\.cloud|n8n\.io)' 2>/dev/null; then
  if ! printf '%s' "$CMD" | grep -qE '/api/v1/data-tables' 2>/dev/null; then
    echo 'BLOCKED: Use n8nac CLI instead of direct API calls (curl/wget/urllib/Invoke-RestMethod). Carve-out: /api/v1/data-tables is allowed — loop the curl from the /n8n-autopilot:data-tables skill, do not switch HTTP tool to dodge this.' >&2
    exit 2
  fi
fi

# ── normalize for the n8nac gates (lib/normalize-n8nac-cmd.mjs): version pin, global --env and a
#    leading `cd <dir> &&` hid push/env commands from the gates below. The gates then run from that
#    dir, with the env the command names, so push-gate's own n8nac calls hit the right instance.
if printf '%s' "$CMD" | grep -q 'n8nac' 2>/dev/null; then
  N_CMD=""; GATE_ENV=""; GATE_CD=""; N_OK=""
  { IFS= read -r -d '' N_CMD && IFS= read -r -d '' GATE_ENV && IFS= read -r -d '' GATE_CD && N_OK=1; } \
    < <(node "$HERE/lib/normalize-n8nac-cmd.mjs" "$CMD" 2>/dev/null)
  # On a normalizer failure keep the original command — the gates still see it as before.
  if [ -n "$N_OK" ] && [ -n "$N_CMD" ]; then
    CMD="$N_CMD"
    [ -n "$GATE_ENV" ] && export N8NAC_ENVIRONMENT="$GATE_ENV"
    # A missing cd target (e.g. a repeated `cd n8n &&` while the shell already sits in n8n/) makes
    # the command fail on its own under `&&`; under `;` it continues here — so check from here.
    [ -n "${GATE_CD:-}" ] && { cd "$GATE_CD" 2>/dev/null || true; }
  fi
fi

# ── 2..4. the fail-closed gates
bash "$HERE/enforce-env.sh" "$CMD" || exit $?
bash "$HERE/push-gate.sh" "$CMD" || exit $?
bash "$HERE/push-lint-gate.sh" "$CMD" || exit $?

# ── 5. advisory only
if printf '%s' "$CMD" | grep -qE 'n8nac[[:space:]]+push' 2>/dev/null; then
  bash "$HERE/ensure-mcp-trigger-setting.sh" "$CMD" 2>&1 || true
fi
exit 0
