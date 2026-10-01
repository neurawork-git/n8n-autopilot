#!/usr/bin/env bash
# sync.sh — push unsynced feedback FINDINGS centrally via the plugin's ingest webhook.
# Transport = a single path (curl POST to the n8n ingest webhook); no fallback chain.
# On any failure: exit 1, mark nothing. No gh/GitHub account needed on the consumer side —
# the ingest workflow (on the maintainer's n8n instance) owns the GitHub token and creates
# ONE ISSUE PER FINDING on the public plugin repo.
# Invoked by the /n8n-autopilot:feedback skill ONLY after the user confirms (PII consent gate).
#
# Only typed `finding` records are pushable — raw event counts are local telemetry that the
# review flow distills INTO findings first. No findings pending -> exit 1 with a hint.
# repoLabel (a customer basename) is PII on a public repo -> stripped from the payload.
# reporter = OS username of the logged-in user (explicitly wanted in the issue).
set -u

WEBHOOK_URL="${N8N_AUTOPILOT_FEEDBACK_URL:-https://n8n.neurawork.app/webhook/autopilot-feedback}"

# --only 1,3  → push just those findings, numbered as `show` lists them (events.ndjson then
# process.ndjson, file order). Backs the "Auswählen" branch of the confirmation prompt; without it
# the skill would offer a choice this script cannot honour. Unselected records stay pending.
ONLY=""
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="$2"; shift 2 ;;
    --only=*) ONLY="${1#--only=}"; shift ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

WORKSPACE="${1:-$PWD}"
STORE="$WORKSPACE/.n8n-autopilot/feedback"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "$STORE" ]; then
  echo "[feedback sync] no local feedback store ($STORE) — nothing to sync." >&2
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "[feedback sync] ERROR: curl not available." >&2
  exit 1
fi

# ── Build the payload: unsynced FINDING records only, repoLabel stripped, wrapped in an
#    envelope with pluginVersion + reporter (OS username). COUNT = finding count.
#    Raw event records are NOT pushable — the review flow distills them into findings.
PAYLOAD="$(mktemp)"
COUNT=$(node -e '
const fs=require("fs"), path=require("path"), os=require("os");
const store=process.argv[1], out=process.argv[2], scriptDir=process.argv[3], only=process.argv[4]||"";
let findings=[]; let nonFindings=0;
for (const f of ["events.ndjson","process.ndjson"]) {
  const p=path.join(store,f); if(!fs.existsSync(p)) continue;
  for (const line of fs.readFileSync(p,"utf8").split("\n")) {
    const s=line.trim(); if(!s) continue;
    try {
      const r=JSON.parse(s);
      if (r.synced===true) continue;
      if (r.kind==="finding") findings.push(r); else nonFindings++;
    } catch(e){}
  }
}
if (!findings.length) { process.stdout.write(nonFindings ? "NOFINDINGS" : "0"); process.exit(0); }
if (only) {
  const want=new Set(only.split(",").map(s=>parseInt(s.trim(),10)).filter(n=>n>=1&&n<=findings.length));
  if (!want.size) { process.stdout.write("BADSELECTION"); process.exit(0); }
  findings=findings.filter((_,i)=>want.has(i+1));
}
// Public target -> strip repoLabel (customer basename).
const clean=findings.map(r=>{const {repoLabel,...rest}=r; return rest;});
let pluginVersion="";
try {
  const pj=path.join(scriptDir,"..","..","..",".claude-plugin","plugin.json");
  pluginVersion=JSON.parse(fs.readFileSync(pj,"utf8")).version||"";
} catch(e){}
let reporter="";
try { reporter=os.userInfo().username||""; } catch(e){}
fs.writeFileSync(out, JSON.stringify({kind:"autopilot-feedback",schemaVersion:2,pluginVersion,reporter,findings:clean}));
process.stdout.write(String(clean.length));
' "$STORE" "$PAYLOAD" "$SCRIPT_DIR" "$ONLY" 2>/dev/null || echo "ERR")

if [ "$COUNT" = "ERR" ]; then
  echo "[feedback sync] ERROR: failed to read local records." >&2
  rm -f "$PAYLOAD"; exit 1
fi
if [ "$COUNT" = "0" ]; then
  echo "[feedback sync] no unsynced records — nothing to push."
  rm -f "$PAYLOAD"; exit 0
fi
if [ "$COUNT" = "NOFINDINGS" ]; then
  echo "[feedback sync] ERROR: pending records are raw signal counts, not findings." >&2
  echo "[feedback sync] Run the /n8n-autopilot:feedback review flow first — it distills the counts into typed, actionable finding records (one issue each). Nothing was pushed." >&2
  rm -f "$PAYLOAD"; exit 1
fi
if [ "$COUNT" = "BADSELECTION" ]; then
  echo "[feedback sync] ERROR: --only '$ONLY' selected no valid finding (numbers are 1..N as listed by \`show\`)." >&2
  rm -f "$PAYLOAD"; exit 1
fi

# ── Defense-in-depth: deterministic PII allowlist gate on the EXACT payload records.
RECORDS_TMP="$(mktemp)"
node -e '
const fs=require("fs");
const payload=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
fs.writeFileSync(process.argv[2], payload.findings.map(r=>JSON.stringify(r)).join("\n")+"\n");
' "$PAYLOAD" "$RECORDS_TMP" 2>/dev/null
if ! node "$SCRIPT_DIR/redact-check.js" "$RECORDS_TMP"; then
  echo "[feedback sync] ERROR: redact-check blocked the push (PII / allowlist violation)." >&2
  echo "[feedback sync] Fix the flagged record(s) — re-run the /n8n-autopilot:feedback review so the LLM redaction neutralizes them — then retry sync. Nothing was pushed." >&2
  rm -f "$RECORDS_TMP" "$PAYLOAD"; exit 1
fi
rm -f "$RECORDS_TMP"

# ── Push: one POST, one path. Success = HTTP 200 from the ingest webhook.
RESPONSE="$(mktemp)"
HTTP_CODE=$(curl -sS -o "$RESPONSE" -w "%{http_code}" \
  -X POST -H "Content-Type: application/json" \
  --data-binary "@$PAYLOAD" --max-time 30 "$WEBHOOK_URL" 2>&1) || HTTP_CODE="000"
rm -f "$PAYLOAD"

if [ "$HTTP_CODE" != "200" ]; then
  echo "[feedback sync] ERROR: ingest webhook returned HTTP $HTTP_CODE:" >&2
  head -c 500 "$RESPONSE" >&2; echo "" >&2
  rm -f "$RESPONSE"; exit 1
fi
ISSUE_URLS=$(node -e 'try{const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write((r.issues||[]).join("\n"));}catch(e){}' "$RESPONSE" 2>/dev/null)
rm -f "$RESPONSE"

# Success — move the pushed records to synced.ndjson.
#   full push : mark ALL unsynced records (the raw event counts were consumed by the review that
#               produced these findings, so they are done too).
#   --only    : mark ONLY the findings actually sent. Marking the rest would silently discard
#               feedback the user deliberately held back — the selection must survive the push.
node -e '
const fs=require("fs"), path=require("path");
const store=process.argv[1], only=process.argv[2]||"";
const synced=path.join(store,"synced.ndjson");
const want=only ? new Set(only.split(",").map(s=>parseInt(s.trim(),10))) : null;
let findingIdx=0;
for (const f of ["events.ndjson","process.ndjson"]) {
  const p=path.join(store,f); if(!fs.existsSync(p)) continue;
  const keep=[], moved=[];
  for (const line of fs.readFileSync(p,"utf8").split("\n")) {
    const s=line.trim(); if(!s) continue;
    let r; try { r=JSON.parse(s); } catch(e){ continue; }
    if (r.synced===true) { keep.push(JSON.stringify(r)); continue; }
    // Index findings in the same order the payload builder did, so --only lines up.
    const isFinding = r.kind==="finding";
    const n = isFinding ? ++findingIdx : null;
    const pushed = want ? (isFinding && want.has(n)) : true;
    if (pushed) { r.synced=true; moved.push(JSON.stringify(r)); } else keep.push(JSON.stringify(r));
  }
  fs.writeFileSync(p, keep.length ? keep.join("\n")+"\n" : "");
  if (moved.length) fs.appendFileSync(synced, moved.join("\n")+"\n");
}
' "$STORE" "$ONLY" 2>/dev/null || true

echo "[feedback sync] pushed $COUNT finding(s), one issue each:"
if [ -n "$ISSUE_URLS" ]; then echo "$ISSUE_URLS" | sed 's/^/  /'; fi
exit 0
