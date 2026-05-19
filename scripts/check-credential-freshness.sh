#!/bin/bash
# check-credential-freshness.sh
# Scans local .workflow.ts files for credential ID references and checks whether
# those IDs exist on the active n8n instance. Flags stale references that would
# cause Class A errors (missing credentials) on push or test.
#
# Usage:
#   bash scripts/check-credential-freshness.sh          # full report
#   bash scripts/check-credential-freshness.sh --quiet  # only print missing entries
#
# Called by: hooks/hooks.json SessionStart (quiet mode)
# Recommends: /n8n-autopilot:sync-credentials when references are stale

QUIET=0
[[ "$1" == "--quiet" ]] && QUIET=1

# Consumer-repo path: the user's CWD when the SessionStart hook fires.
# CLAUDE_PLUGIN_ROOT points at the *plugin install* dir, not the workspace.
REPO_DIR="$PWD"
WORKFLOWS_DIR="$REPO_DIR/workflows"

if [ ! -d "$WORKFLOWS_DIR" ]; then
  exit 0
fi

# Pattern: credentials: { <type>: { id: '<id>', name: '<name>' } }
# Only match `id: '...'` that follows `credentials:` on the same line — avoids
# matching JSON-schema property names like `id: 'address'` inside parameters.
REFS=$(grep -rhoE "credentials:[[:space:]]*\{[^}]*id:[[:space:]]*'[A-Za-z0-9]+'" "$WORKFLOWS_DIR" --include="*.workflow.ts" 2>/dev/null \
       | grep -oE "id:[[:space:]]*'[A-Za-z0-9]+'" \
       | sed -E "s/id:[[:space:]]*'([A-Za-z0-9]+)'/\1/" \
       | sort -u)

if [ -z "$REFS" ]; then
  [ "$QUIET" -eq 0 ] && echo "ℹ️  No credential references found in workflows/."
  exit 0
fi

# Fetch credential IDs from instance (silent on failure — n8nac may not be initialized)
LIVE_IDS=$(npx --yes n8nac credential list --json 2>/dev/null \
           | node -e "
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
  try { const j=JSON.parse(d); (Array.isArray(j)?j:j.credentials||[]).forEach(c=>console.log(c.id)); }
  catch(e){}
});" 2>/dev/null)

if [ -z "$LIVE_IDS" ]; then
  [ "$QUIET" -eq 0 ] && echo "ℹ️  check-credential-freshness: skipping (n8nac credential list unavailable — run 'npx n8nac setup --mode connect-existing')."
  exit 0
fi

MISSING_COUNT=0
MISSING_LIST=""

while IFS= read -r id; do
  [ -z "$id" ] && continue
  if ! echo "$LIVE_IDS" | grep -qx "$id"; then
    MISSING_COUNT=$((MISSING_COUNT + 1))
    MISSING_LIST="$MISSING_LIST  ⚠️  STALE    credential id=$id (referenced in workflows/, not found on instance)\n"
  fi
done <<< "$REFS"

if [ "$MISSING_COUNT" -gt 0 ]; then
  echo "=== Credential Freshness Check ==="
  printf "%b" "$MISSING_LIST"
  echo ""
  echo "$MISSING_COUNT stale credential reference(s) found. Run: /n8n-autopilot:sync-credentials --fix-workflows"
  # Machine-parsable signal for Claude to auto-trigger the action (see CLAUDE.md Auto-Reactions).
  # --fix-workflows rewrites the stale IDs by joining on credential name.
  echo "AUTOPILOT_ACTION_REQUIRED: /n8n-autopilot:sync-credentials --fix-workflows"
  exit 1
fi

[ "$QUIET" -eq 0 ] && echo "All credential references resolve on the active n8n instance."
exit 0
