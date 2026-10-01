#!/usr/bin/env bash
# test-feedback-sync.sh — guards the feedback push against losing records.
#
# The dangerous half is the marking step: on success sync.sh moves records to synced.ndjson, and a
# partial push (`--only`, backing the "Auswählen" branch of the confirmation prompt) must move ONLY
# what it actually sent. Marking the rest would silently discard feedback the user deliberately held
# back — invisible, because the local store is gitignored and nothing would ever be re-sent.
#
# Runs against a throwaway store and a local HTTP stub. Never touches the real ingest webhook.
#
# Usage: bash scripts/test-feedback-sync.sh

set -u
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC="$SCRIPTS/../skills/feedback/scripts/sync.sh"
PORT=8731
PASS=0; FAIL=0

check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "ok   — $1"; PASS=$((PASS+1))
  else echo "FAIL — $1"; echo "       expected: $2"; echo "       actual:   $3"; FAIL=$((FAIL+1)); fi
}

mkstore() { # mkstore <dir>
  mkdir -p "$1/.n8n-autopilot/feedback"
  cat > "$1/.n8n-autopilot/feedback/events.ndjson" <<'JSON'
{"kind":"finding","schemaVersion":2,"type":"bug","severity":"high","area":"a","title":"F1","observed":"x","expected":"y"}
{"kind":"event","signals":{"validate_fail":2}}
{"kind":"finding","schemaVersion":2,"type":"bug","severity":"low","area":"b","title":"F2","observed":"x","expected":"y"}
{"kind":"finding","schemaVersion":2,"type":"bug","severity":"low","area":"c","title":"F3","observed":"x","expected":"y"}
JSON
}

titles() { # titles <ndjson-path>  -> comma-joined titles/kinds, "" when absent
  [ -f "$1" ] || { echo ""; return; }
  node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{
    const t=d.trim(); if(!t){process.stdout.write("");return;}
    process.stdout.write(t.split("\n").map(l=>{try{const r=JSON.parse(l);return r.title||r.kind}catch(e){return"?"}}).join(","));
  })' < "$1"
}

# HTTP stub: echoes back one issue URL per finding and records what it received.
GOT="$(mktemp)"
node -e '
const fs=require("fs");
require("http").createServer((q,s)=>{let b="";q.on("data",c=>b+=c);q.on("end",()=>{
  const p=JSON.parse(b);
  fs.appendFileSync(process.argv[1], p.findings.map(f=>f.title).join(",")+"\n");
  s.writeHead(200,{"Content-Type":"application/json"});
  s.end(JSON.stringify({issues:p.findings.map((_,i)=>"http://stub/"+i)}));
});}).listen(process.argv[2])' "$GOT" "$PORT" &
STUB=$!
trap 'kill $STUB 2>/dev/null; rm -f "$GOT"' EXIT
sleep 1

URL="http://127.0.0.1:$PORT/"

# === 1. partial push — only the selected findings leave, the rest stay pending ==============
T1="$(mktemp -d)"; mkstore "$T1"
N8N_AUTOPILOT_FEEDBACK_URL="$URL" bash "$SYNC" --only 1,3 "$T1" >/dev/null 2>&1
check "--only sends exactly the selected findings"      "F1,F3"    "$(tail -1 "$GOT")"
check "--only keeps unselected records pending"         "event,F2" "$(titles "$T1/.n8n-autopilot/feedback/events.ndjson")"
check "--only marks only what it sent"                  "F1,F3"    "$(titles "$T1/.n8n-autopilot/feedback/synced.ndjson")"
rm -rf "$T1"

# === 2. full push — everything unsynced is sent and marked, store left empty =================
T2="$(mktemp -d)"; mkstore "$T2"
N8N_AUTOPILOT_FEEDBACK_URL="$URL" bash "$SYNC" "$T2" >/dev/null 2>&1
check "full push sends every finding"                   "F1,F2,F3"       "$(tail -1 "$GOT")"
check "full push leaves nothing pending"                ""               "$(titles "$T2/.n8n-autopilot/feedback/events.ndjson")"
check "full push marks findings AND consumed counts"    "F1,event,F2,F3" "$(titles "$T2/.n8n-autopilot/feedback/synced.ndjson")"
rm -rf "$T2"

# === 3. bad selection — refuse, send nothing, mark nothing ===================================
T3="$(mktemp -d)"; mkstore "$T3"
BEFORE="$(tail -1 "$GOT")"
N8N_AUTOPILOT_FEEDBACK_URL="$URL" bash "$SYNC" --only 99 "$T3" >/dev/null 2>&1
check "invalid --only pushes nothing"                   "$BEFORE"        "$(tail -1 "$GOT")"
check "invalid --only marks nothing"                    ""               "$(titles "$T3/.n8n-autopilot/feedback/synced.ndjson")"
rm -rf "$T3"

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
