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
const fs=require('fs'),path=require('path');
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
  try {
    const i=d.indexOf('[');
    const arr=i>=0?JSON.parse(d.slice(i)):[];
    // Index every .workflow.ts under ./workflows by basename, so the check does not
    // depend on resolving the active environment's workflowsPath.
    const onDisk=new Set();
    (function walk(dir){
      let ents=[]; try{ ents=fs.readdirSync(dir,{withFileTypes:true}); }catch(e){ return; }
      for(const e of ents){
        if(e.isDirectory()) walk(path.join(dir,e.name));
        else if(e.name.endsWith('.workflow.ts')) onDisk.add(e.name);
      }
    })(path.join(process.cwd(),'workflows'));
    // n8nac can report EXIST_ONLY_REMOTELY for a workflow whose file is right there on
    // disk (observed 2026-07-28: correct filename, matching id in the file, live state
    // entry — and neither pull nor fetch clears it). Pulling that is a no-op, so the
    // mandatory signal would repeat forever. Only real absence counts as drift.
    const flagged=(Array.isArray(arr)?arr:[]).filter(w=>/REMOTE/i.test(String(w.status||''))&&!w.isArchived);
    const drift=flagged.filter(w=>!w.filename||!onDisk.has(w.filename));
    const phantom=flagged.filter(w=>w.filename&&onDisk.has(w.filename));
    console.log(drift.length);
    console.log(phantom.length);
    drift.slice(0,25).forEach(w=>console.log('  ⚠️  '+w.id+'  '+(w.name||'')));
    phantom.slice(0,25).forEach(w=>console.log('  ~   '+w.id+'  '+(w.name||'')));
  } catch(e){ console.log('-1'); console.log('0'); }
});" 2>/dev/null)

COUNT=$(printf "%s" "$REPORT" | head -1)
PHANTOM=$(printf "%s" "$REPORT" | sed -n '2p')
NAMES=$(printf "%s" "$REPORT" | tail -n +3 | grep '⚠️' )
PHANTOM_NAMES=$(printf "%s" "$REPORT" | tail -n +3 | grep '~   ')

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

if [ -n "$PHANTOM" ] && [ "$PHANTOM" -gt 0 ] 2>/dev/null; then
  echo "=== Mirror Drift Check ==="
  echo "INFO: n8nac reports $PHANTOM workflow(s) as remote-only, but the file is present locally:"
  printf "%s\n" "$PHANTOM_NAMES"
  echo "      This is an n8nac status artefact, not drift — pull/fetch do not clear it."
  echo "      No auto-action emitted (mirror-sync would be a no-op). Mirror is complete."
  exit 0
fi

[ "$QUIET" -eq 0 ] && echo "Local repo mirrors the instance (no remote-only workflows)."
exit 0
