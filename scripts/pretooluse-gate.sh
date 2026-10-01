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

# ── 1. curl-block — direct REST calls against the n8n API bypass every gate below.
if printf '%s' "$CMD" | grep -qE '(curl|wget|urllib|Invoke-RestMethod|Invoke-WebRequest|requests\.|fetch\().*(/api/v1|n8n\.cloud|n8n\.io)' 2>/dev/null; then
  if ! printf '%s' "$CMD" | grep -qE '/api/v1/data-tables' 2>/dev/null; then
    echo 'BLOCKED: Use n8nac CLI instead of direct API calls (curl/wget/urllib/Invoke-RestMethod). Carve-out: /api/v1/data-tables is allowed — loop the curl from the /n8n-autopilot:data-tables skill, do not switch HTTP tool to dodge this.' >&2
    exit 2
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
