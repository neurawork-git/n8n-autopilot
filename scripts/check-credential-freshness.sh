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

  # A stale ID is NOT automatically fixable. --fix-workflows joins on credential *name*
  # within the pinned project; if that name resolves nowhere, the reference is an orphan
  # and the auto-action is a guaranteed no-op. Ask the fixer (exit 3 == "would rewrite")
  # instead of guessing — a mandatory signal that cannot be satisfied fires every session
  # and trains everyone to ignore the whole auto-reaction mechanism.
  FIXER="${CLAUDE_PLUGIN_ROOT:-.}/skills/sync-credentials/scripts/fix-workflows.js"
  if [ -f "$FIXER" ]; then
    node "$FIXER" --dry-run >/dev/null 2>&1
    if [ "$?" -eq 3 ]; then
      echo "$MISSING_COUNT stale credential reference(s) found. Run: /n8n-autopilot:sync-credentials --fix-workflows"
      echo "AUTOPILOT_ACTION_REQUIRED: /n8n-autopilot:sync-credentials --fix-workflows"
      exit 1
    fi
    echo "INFO: none of these resolve by credential name in the pinned project — they are orphans,"
    echo "      not stale IDs. --fix-workflows cannot repair them (no auto-action emitted)."
    echo "      Fix: create the credential on the instance, or drop the reference from the workflow."
    echo "      Full list: node \"\$CLAUDE_PLUGIN_ROOT/skills/sync-credentials/scripts/fix-workflows.js\" --dry-run"
    exit 1
  fi

  # Fixer not reachable (unusual): fall back to the old behaviour rather than staying silent.
  echo "$MISSING_COUNT stale credential reference(s) found. Run: /n8n-autopilot:sync-credentials --fix-workflows"
  echo "AUTOPILOT_ACTION_REQUIRED: /n8n-autopilot:sync-credentials --fix-workflows"
  exit 1
fi

[ "$QUIET" -eq 0 ] && echo "All credential references resolve on the active n8n instance."
exit 0
