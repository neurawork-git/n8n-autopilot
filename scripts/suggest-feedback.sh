#!/usr/bin/env bash
# suggest-feedback.sh — Stop hook: when a work turn ends in a session that did real n8nac work
# and no feedback finding was recorded yet, BLOCK the stop once (exit 2) and instruct Claude to
# actively offer /n8n-autopilot:feedback to the user. Fires at most once per session (marker file),
# never loops (stop_hook_active guard), stays silent in sessions without n8nac activity.
set -u

INPUT=$(cat 2>/dev/null || true)

eval "$(node -e '
let inp="";process.stdin.on("data",d=>inp+=d).on("end",()=>{
  let j={};try{j=JSON.parse(inp)}catch(e){}
  const q=s=>String(s||"").replace(/\\/g,"/").replace(/[^A-Za-z0-9_\/:., -]/g,"");
  console.log("SID=\""+q(j.session_id)+"\"");
  console.log("TRANSCRIPT=\""+q(j.transcript_path)+"\"");
  console.log("ACTIVE="+(j.stop_hook_active?1:0));
});' <<<"$INPUT" 2>/dev/null || echo 'SID=; TRANSCRIPT=; ACTIVE=0')"

# Never loop: if this stop was already forced by a stop hook, let it pass.
[ "${ACTIVE:-0}" = "1" ] && exit 0
[ -n "${SID:-}" ] || exit 0
[ -n "${TRANSCRIPT:-}" ] && [ -f "$TRANSCRIPT" ] || exit 0

WORKSPACE="${CLAUDE_PROJECT_DIR:-$PWD}"
STORE="$WORKSPACE/.n8n-autopilot/feedback"
MARKER="$STORE/.suggested-$SID"

# Once per session.
[ -f "$MARKER" ] && exit 0

# Only fire when the session actually did n8nac work.
N8NAC_CALLS=$(grep -c "npx n8nac" "$TRANSCRIPT" 2>/dev/null || true)
case "${N8NAC_CALLS:-0}" in *[!0-9]*) N8NAC_CALLS=0;; esac
[ "${N8NAC_CALLS:-0}" -ge 3 ] || exit 0

# Skip if this session already recorded a finding (feedback already happened).
if [ -f "$STORE/process.ndjson" ] && grep -q "\"sessionId\":\"$SID\"" "$STORE/process.ndjson" 2>/dev/null; then
  exit 0
fi

mkdir -p "$STORE" 2>/dev/null || exit 0
: > "$MARKER"

cat >&2 <<EOF
FEEDBACK GATE: This session contains real n8n-autopilot work ($N8NAC_CALLS n8nac calls) and no feedback finding has been recorded yet. Before ending your turn, ACTIVELY propose the feedback loop to the user NOW: summarize in 1-2 sentences which frictions/learnings this session surfaced and ask whether to run /n8n-autopilot:feedback review (distills them into typed findings, one GitHub issue each; push stays consent-gated). If the user declines, respect it — this gate fires only once per session.
EOF
exit 2
