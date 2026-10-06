#!/usr/bin/env bash
# check-feedback-pending.sh — SessionStart nudge for the autopilot feedback loop.
# Counts unsynced feedback records (synced:false/absent) in the consumer repo's local store and
# emits an INFO: line if any are pending. Surfaces only — NEVER AUTOPILOT_ACTION_REQUIRED:, because
# giving/syncing feedback requires user consent and must not auto-fire.
#
# Usage: bash scripts/check-feedback-pending.sh [--quiet]
# Called by: hooks/hooks.json SessionStart (quiet mode).

# Opt-out: N8N_AUTOPILOT_NO_FEEDBACK=1 switches the whole feedback loop off (capture, SessionStart
# nudge, Stop gate). Set it in the env block of a settings.json so it survives plugin updates.
[ "${N8N_AUTOPILOT_NO_FEEDBACK:-0}" = "1" ] && exit 0

# Consumer-repo path: the user's CWD when the SessionStart hook fires.
# CLAUDE_PLUGIN_ROOT points at the *plugin install* dir, not the workspace.
REPO_DIR="$PWD"
STORE="$REPO_DIR/.n8n-autopilot/feedback"

[ -d "$STORE" ] || exit 0

N=$(node -e '
const fs=require("fs"), path=require("path");
const store=process.argv[1];
let pending=0;
for (const f of ["events.ndjson","process.ndjson"]) {
  const p=path.join(store,f);
  if (!fs.existsSync(p)) continue;
  for (const line of fs.readFileSync(p,"utf8").split("\n")) {
    const s=line.trim(); if(!s) continue;
    try { const r=JSON.parse(s); if (r.synced!==true) pending++; } catch(e){}
  }
}
process.stdout.write(String(pending));
' "$STORE" 2>/dev/null || echo 0)

if [ "${N:-0}" -gt 0 ] 2>/dev/null; then
  echo "INFO: $N autopilot feedback record(s) pending — run \`/n8n-autopilot:feedback\` to add process feedback, or \`/n8n-autopilot:feedback sync\` to push them centrally"
fi
exit 0
