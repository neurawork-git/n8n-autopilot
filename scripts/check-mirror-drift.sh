#!/bin/bash
# check-mirror-drift.sh
# Detects workflows that exist on the active n8n instance but have NO local file
# (the local repo is supposed to mirror the instance). Remote-only workflows mean
# the local-first invariant relied on by /n8n-autopilot:build-workflow-v2 (edit flow)
# is broken — emit a machine-parsable action signal to pull them.
#
# Only fires on REAL drift (remote-only workflows present) — never a blind
# every-session pull-all.
#
# Usage:
#   bash scripts/check-mirror-drift.sh          # full report
#   bash scripts/check-mirror-drift.sh --quiet  # only print when drift exists
#
# Called by: hooks/hooks.json SessionStart (quiet mode)
# Recommends: /n8n-autopilot:mirror-sync when remote-only workflows exist

QUIET=0
[[ "$1" == "--quiet" ]] && QUIET=1

# `list --json` reflects the workspace-pinned project; needs a bound workspace.
LIST=$(npx --yes n8nac list --json 2>/dev/null)

if [ -z "$LIST" ]; then
  [ "$QUIET" -eq 0 ] && echo "ℹ️  check-mirror-drift: skipping (n8nac list unavailable — run 'npx n8nac setup --mode connect-existing')."
  exit 0
fi

# Parse from the first '[' (n8nac prints a "- Listing…" progress line first).
# Count + name remote-only, non-archived workflows. Status match is case-insensitive
# on /REMOTE/ to cover both REMOTE_ONLY and EXIST_ONLY_REMOTELY across versions.
REPORT=$(printf "%s" "$LIST" | node -e "
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
  try {
    const i=d.indexOf('[');
    const arr=i>=0?JSON.parse(d.slice(i)):[];
    const drift=(Array.isArray(arr)?arr:[]).filter(w=>/REMOTE/i.test(String(w.status||''))&&!w.isArchived);
    console.log(drift.length);
    drift.slice(0,25).forEach(w=>console.log('  ⚠️  '+w.id+'  '+(w.name||'')));
  } catch(e){ console.log('-1'); }
});" 2>/dev/null)

COUNT=$(printf "%s" "$REPORT" | head -1)
NAMES=$(printf "%s" "$REPORT" | tail -n +2)

if [ "$COUNT" = "-1" ] || [ -z "$COUNT" ]; then
  [ "$QUIET" -eq 0 ] && echo "ℹ️  check-mirror-drift: could not parse 'n8nac list --json' output."
  exit 0
fi

if [ "$COUNT" -gt 0 ]; then
  echo "=== Mirror Drift Check ==="
  echo "$COUNT workflow(s) exist on the instance but not locally:"
  printf "%s\n" "$NAMES"
  echo ""
  echo "Local repo is not a complete mirror. Run: /n8n-autopilot:mirror-sync"
  # Machine-parsable signal for Claude to auto-trigger (see CLAUDE.md Auto-Reactions).
  echo "AUTOPILOT_ACTION_REQUIRED: /n8n-autopilot:mirror-sync"
  exit 1
fi

[ "$QUIET" -eq 0 ] && echo "Local repo mirrors the instance (no remote-only workflows)."
exit 0
