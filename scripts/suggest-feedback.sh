#!/usr/bin/env bash
# suggest-feedback.sh — Stop hook: when a work turn ends in a session that did real n8nac work
# and no feedback finding was recorded yet, BLOCK the stop once (exit 2) and instruct Claude to
# actively offer /n8n-autopilot:feedback to the user. Fires at most once per session (marker file),
# never loops (stop_hook_active guard), stays silent in sessions without n8nac activity.
set -u

# Opt-out: N8N_AUTOPILOT_NO_FEEDBACK=1 switches the whole feedback loop off (capture, SessionStart
# nudge, Stop gate). Set it in the env block of a settings.json so it survives plugin updates.
[ "${N8N_AUTOPILOT_NO_FEEDBACK:-0}" = "1" ] && exit 0
# N8N_AUTOPILOT_NO_FEEDBACK_GATE=1 switches off only this Stop gate.
[ "${N8N_AUTOPILOT_NO_FEEDBACK_GATE:-0}" = "1" ] && exit 0

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

# Only in sessions with the n8n mode on (scripts/lib/n8n-mode.sh).
. "$(dirname "${BASH_SOURCE[0]}")/lib/n8n-mode.sh"
n8n_mode_active "$SID" || exit 0

WORKSPACE="${CLAUDE_PROJECT_DIR:-$PWD}"
STORE="$WORKSPACE/.n8n-autopilot/feedback"
MARKER="$STORE/.suggested-$SID"

# Once per session.
[ -f "$MARKER" ] && exit 0

# Only fire when the session actually did n8nac work: count shell tool calls that ran n8nac.
# A plain `grep -c` over the transcript also counted SessionStart probe output, skill listings and
# CLAUDE.md hints mentioning `npx n8nac` — the gate then fired in sessions without any n8n work.
N8NAC_CALLS=$(node -e '
const fs=require("fs"); let n=0;
for (const line of fs.readFileSync(process.argv[1],"utf8").split("\n")) {
  if (!line.includes("n8nac")) continue;
  let o; try { o=JSON.parse(line) } catch(e) { continue }
  if (o.type!=="assistant" || !Array.isArray(o.message&&o.message.content)) continue;
  for (const b of o.message.content)
    if (b.type==="tool_use" && /^(Bash|PowerShell)$/.test(b.name) && /\bn8nac\b/.test(String((b.input||{}).command||""))) n++;
}
console.log(n);' "$TRANSCRIPT" 2>/dev/null || echo 0)
case "${N8NAC_CALLS:-0}" in *[!0-9]*) N8NAC_CALLS=0;; esac
[ "${N8NAC_CALLS:-0}" -ge 3 ] || exit 0

# Skip if this session already recorded a finding (feedback already happened).
if [ -f "$STORE/process.ndjson" ] && grep -q "\"sessionId\":\"$SID\"" "$STORE/process.ndjson" 2>/dev/null; then
  exit 0
fi

mkdir -p "$STORE" 2>/dev/null || exit 0
: > "$MARKER"

# Block the stop via the JSON decision API (exit 0) — an exit-2/stderr block renders as a red
# "Stop hook error" line in the client, which reads like a crash. Same effect, clean UI.
node -e '
const reason = "FEEDBACK GATE: This session contains real n8n-autopilot work (" + process.argv[1] +
  " n8nac calls) and no feedback finding has been recorded yet. Before ending your turn, ACTIVELY " +
  "propose the feedback loop to the user NOW: summarize in 1-2 sentences which frictions/learnings " +
  "this session surfaced and ask whether to run /n8n-autopilot:feedback review (distills them into " +
  "typed findings, one GitHub issue each; push stays consent-gated). If the user declines, respect " +
  "it — this gate fires only once per session.";
console.log(JSON.stringify({ decision: "block", reason }));
' "$N8NAC_CALLS" 2>/dev/null || exit 0
exit 0
