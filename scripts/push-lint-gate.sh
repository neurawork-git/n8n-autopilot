#!/usr/bin/env bash
# push-lint-gate.sh — Block `n8nac push <file>` unless
#   (1) every node type + typeVersion of the compiled workflow exists on the RUNNING instance —
#       scripts/instance-node-check.mjs asks the instance's own MCP `get_node_types`. n8nac's push
#       preflight only warns here and falls back to its bundled catalogue, which is stamped for a
#       different n8n version (#85, #82, #62). Needs native MCP configured for the session env.
#   (2) scripts/lint-workflow.py passes on the compiled JSON (graph shape, masked failures,
#       expressions, availableInMCP) — what no schema validator looks at.
# Default = block. Fail-closed.
#
# Called by: hooks/hooks.json PreToolUse(Bash) — receives the full bash command via $1.
# Runs AFTER push-gate.sh (drift) in the hook list; both must pass.
#
# Exit codes:
#   0 — allow (no push detected, gate passed, or explicit override)
#   2 — BLOCK (Claude PreToolUse contract)
#
# Override (only after the user explicitly accepted shipping a failing workflow):
#   N8N_AUTOPILOT_SKIP_LINT=1 <command>

set -u

INPUT="${1:-}"
[ -z "$INPUT" ] && exit 0
echo "$INPUT" | grep -qE 'n8nac[[:space:]]+push([[:space:]]|$)' 2>/dev/null || exit 0

if [ "${N8N_AUTOPILOT_SKIP_LINT:-0}" = "1" ]; then
  echo "[push-lint] N8N_AUTOPILOT_SKIP_LINT=1 — quality gate bypassed."
  exit 0
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$HERE/lint-workflow.py"

# ── Resolve the pushed file: first non-flag token after `push`, honouring a leading `cd <dir> &&`.
FILE=$(python - "$INPUT" <<'PY'
import shlex, sys
cmd = sys.argv[1]
try:
    toks = shlex.split(cmd, posix=True)
except ValueError:
    toks = cmd.split()
cd = None
for i, t in enumerate(toks):
    if t == "cd" and i + 1 < len(toks):
        cd = toks[i + 1]
    if t == "push":
        rest = [x for x in toks[i + 1:] if not x.startswith("--") and x not in ("&&", ";", "||", "|")]
        for x in rest:
            if x in ("echo", "$?", "EXITCODE=$?"):
                break
            import os
            print(os.path.join(cd, x) if cd and not os.path.isabs(x) else x)
            break
        break
PY
)

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  cat >&2 <<EOF
[push-lint] BLOCKED — cannot resolve the pushed file from the command (got: '${FILE:-<none>}').
Run push from the repo root with a repo-relative or absolute path, one file per command:
  npx n8nac push "<path>.workflow.ts" --verify
EOF
  exit 2
fi

# n8nac is Node: it needs a Windows path under Git-Bash.
FILE_N="$FILE"; command -v cygpath >/dev/null 2>&1 && FILE_N="$(cygpath -w "$FILE")"
TMP="${TMPDIR:-/tmp}/push-lint-$$.json"; TMP_N="$TMP"; command -v cygpath >/dev/null 2>&1 && TMP_N="$(cygpath -w "$TMP")"
trap 'rm -f "$TMP"' EXIT

# ── compile once, both checks read the same JSON
COUT=$(npx --yes n8nac convert "$FILE_N" -o "$TMP_N" -f 2>&1) || {
  echo "[push-lint] BLOCKED — \`n8nac convert\` failed for $FILE:" >&2; echo "$COUT" | tail -5 >&2; exit 2; }

# ── 1. node types + typeVersions exist on the instance
IOUT=$(node "$HERE/instance-node-check.mjs" "$TMP_N" 2>/dev/null); IRC=$?
if [ $IRC -eq 2 ]; then
  ERR=$(printf '%s' "$IOUT" | python -c 'import json,sys; print(json.load(sys.stdin).get("error","no output"))' 2>/dev/null || echo "no output")
  cat >&2 <<EOF
[push-lint] BLOCKED — cannot check node versions against the instance: $ERR
Configure native MCP for this env once, in YOUR terminal (token: n8n UI → Settings → MCP; it must be
PIPED in — bare --token-stdin waits silently). Commands: docs/rules/testing.md, e.g. PowerShell:
  \$t = Read-Host "n8n MCP Token" -MaskInput; \$t | npx n8nac native-mcp configure ${N8NAC_ENVIRONMENT:-<env>} --token-stdin --level 2
EOF
  exit 2
elif [ $IRC -ne 0 ]; then
  echo "[push-lint] BLOCKED — nodes the instance does not have ($FILE):" >&2
  printf '%s' "$IOUT" | python -c '
import json,sys
for b in json.load(sys.stdin)["blockers"]:
    print("  BLOCK  %-45s v%-5s %s  (%s)" % (b["type"], b["version"], b["msg"], ", ".join(b["nodes"])))' >&2
  echo "Use a version the instance lists: native MCP get_node_types / search_nodes, or a node already running there (.n8n-autopilot/instance-brief.md)." >&2
  exit 2
fi
printf '%s' "$IOUT" | python -c '
import json,sys
for w in json.load(sys.stdin).get("warnings",[]):
    print("[push-lint] warn  %s v%s %s" % (w["type"], w["version"], w["msg"]))' >&2 || true

# ── 1b. every top-level parameter exists for the node's typeVersion (version-gated schema, #94 #84)
POUT=$(python "$HERE/param-version-check.py" "$TMP"); PRC=$?
if [ $PRC -eq 1 ]; then
  echo "[push-lint] BLOCKED — parameters that do not exist for the node's typeVersion ($FILE):" >&2
  echo "$POUT" | grep '^BLOCK' >&2
  echo "n8n ignores such keys silently. Move the parameter to where this version keeps it (npx n8nac skills node-info <type> --json → schema.properties[].displayOptions.show['@version']) or use the version that has it." >&2
  exit 2
elif [ $PRC -ne 0 ]; then
  echo "[push-lint] warn  parameter-version check could not run: $POUT" >&2
fi
echo "$POUT" | grep '^warn' | sed 's/^/[push-lint] /' >&2 || true

# ── 2. deterministic lint
LOUT=$(python "$LINT" "$TMP"); LRC=$?
if [ $LRC -ne 0 ]; then
  echo "[push-lint] BLOCKED — design-quality lint failed for $FILE" >&2
  echo "$LOUT" >&2
  echo "Rules: $HERE/lint-workflow.py (docstring)." >&2
  exit 2
fi
echo "$LOUT" | grep '^warn' >&2 || true
exit 0
