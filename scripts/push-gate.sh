#!/usr/bin/env bash
# push-gate.sh — Block `n8nac push` and `n8nac resolve --mode keep-current`
# when remote workflow has drifted (CONFLICT) or when the local file has not
# been re-fetched since the last remote modification. Default = block; opt out
# via env var.
#
# Called by: hooks/hooks.json PreToolUse(Bash) — receives the full bash command
# on stdin via $1.
#
# Exit codes:
#   0 — allow (no push detected, or push is safe, or override env set)
#   2 — BLOCK (Claude PreToolUse contract: non-zero blocks the tool call)

set -u

INPUT="${1:-}"
[ -z "$INPUT" ] && exit 0

# ── Carve-out: explicit user override
if [ "${N8N_AUTOPILOT_ALLOW_LOCAL_WINS:-0}" = "1" ]; then
  echo "[push-gate] N8N_AUTOPILOT_ALLOW_LOCAL_WINS=1 — drift check bypassed."
  exit 0
fi

# ── Detect `n8nac resolve <id> --mode keep-current` (or --mode keep-local)
if echo "$INPUT" | grep -qE 'n8nac[[:space:]]+resolve[[:space:]]+[A-Za-z0-9]+[[:space:]]+--mode[[:space:]]+(keep-current|keep-local|local-wins)' 2>/dev/null; then
  cat >&2 <<EOF
[push-gate] BLOCKED — \`n8nac resolve --mode keep-current\` overwrites remote with local state.

This silently destroys any change made on the n8n instance since the last pull.
Plugin policy: explicit user opt-in required.

To proceed (only after confirming the remote change should be discarded):
  N8N_AUTOPILOT_ALLOW_LOCAL_WINS=1 <command>

Safer alternatives:
  npx n8nac pull <id>                       # remote wins, sync local
  npx n8nac resolve <id> --mode keep-remote # explicit remote-wins
EOF
  exit 2
fi

# ── Detect `n8nac push <path>`
if ! echo "$INPUT" | grep -qE 'n8nac[[:space:]]+push[[:space:]]+' 2>/dev/null; then
  exit 0
fi

# Extract the path argument (first non-flag token after `push`)
PUSH_PATH=$(echo "$INPUT" \
  | sed -nE 's/.*n8nac[[:space:]]+push[[:space:]]+((--[a-zA-Z-]+[[:space:]]+)*)([^[:space:]]+).*/\3/p' \
  | head -1)

if [ -z "$PUSH_PATH" ]; then
  exit 0
fi

# Resolve relative path against CWD
if [ ! -f "$PUSH_PATH" ]; then
  # Path may be quoted differently — try a looser extraction
  PUSH_PATH=$(echo "$INPUT" | grep -oE "[^[:space:]'\"]+\.workflow\.ts" | head -1)
  [ -z "$PUSH_PATH" ] || [ ! -f "$PUSH_PATH" ] && exit 0
fi

# Extract workflow ID from `@workflow({ id: '...' })`
WF_ID=$(grep -oE "id:[[:space:]]*['\"][A-Za-z0-9]{10,}['\"]" "$PUSH_PATH" 2>/dev/null \
        | head -1 \
        | grep -oE "['\"][A-Za-z0-9]{10,}['\"]" \
        | tr -d "'\"")

if [ -z "$WF_ID" ]; then
  # No id → new workflow creation, nothing to overwrite. Allow.
  exit 0
fi

# ── Refresh remote cache then read status
npx --yes n8nac fetch "$WF_ID" >/dev/null 2>&1 || true

STATUS=$(npx --yes n8nac list --search "$WF_ID" --json 2>/dev/null \
         | node -e "
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
  try {
    const arr=JSON.parse(d);
    const hit=(Array.isArray(arr)?arr:[]).find(w=>w.id==='$WF_ID');
    process.stdout.write(hit ? (hit.status||'UNKNOWN') : 'NOT_FOUND');
  } catch(e){ process.stdout.write('PARSE_ERROR'); }
});" 2>/dev/null || echo "PROBE_ERROR")

case "$STATUS" in
  TRACKED)
    # Local == remote at last fetch. Safe to push.
    exit 0
    ;;
  CONFLICT|MODIFIED_BOTH|DIVERGED)
    cat >&2 <<EOF
[push-gate] BLOCKED — remote drift detected for workflow $WF_ID

\`npx n8nac list --search $WF_ID\` reports status=$STATUS — the workflow has
been modified on n8n since the last local pull. Pushing now would silently
overwrite those remote changes.

Reconcile WITHOUT losing your local edit (avoids the re-type churn):
  cp "$PUSH_PATH" "$PUSH_PATH.local-bak"  # 1. keep your local change
  npx n8nac pull $WF_ID                    # 2. remote wins, sync local
  # 3. diff $PUSH_PATH.local-bak against the pulled file and re-apply your
  #    intended change as a small patch, then:  npx n8nac push $PUSH_PATH --verify

Alternatives:
  npx n8nac resolve $WF_ID                 # interactive resolution

To force local-wins anyway (destroys remote changes):
  N8N_AUTOPILOT_ALLOW_LOCAL_WINS=1 <re-run your push command>
EOF
    exit 2
    ;;
  REMOTE_ONLY)
    cat >&2 <<EOF
[push-gate] BLOCKED — workflow $WF_ID exists ONLY on the remote.

The local file references an existing remote workflow, but n8nac has no local
tracking entry. Pull first so the local file reflects current remote state
(back up your local edit first so you can re-apply it):
  cp "$PUSH_PATH" "$PUSH_PATH.local-bak"
  npx n8nac pull $WF_ID

Override (rare — only if you intend to fully replace the remote with local):
  N8N_AUTOPILOT_ALLOW_LOCAL_WINS=1 <re-run your push command>
EOF
    exit 2
    ;;
  LOCAL_ONLY|NOT_FOUND|UNKNOWN|PROBE_ERROR|PARSE_ERROR|"")
    # Either truly new, or status probe failed — allow (n8nac itself will
    # surface validation errors). Do NOT block on uncertain signals.
    exit 0
    ;;
  *)
    # Unknown status string — be permissive but log.
    echo "[push-gate] WARN: unrecognized status '$STATUS' for $WF_ID — allowing." >&2
    exit 0
    ;;
esac
