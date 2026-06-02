#!/usr/bin/env bash
# sync.sh — push unsynced feedback records centrally as ONE labelled GitHub issue.
# Transport = a single path (gh issue create); no fallback chain. On any failure: exit 1, mark nothing.
# Invoked by the /n8n-autopilot:feedback skill ONLY after the user confirms (PII consent gate).
#
# Records go to the INTERNAL repo. Body carries the NDJSON records (the "internal-repo file" content)
# + a human summary. Pipeline: see feedback SKILL.md.
set -u

REPO="neurawork-git/n8n-autopilot-internal"
WORKSPACE="${1:-$PWD}"
STORE="$WORKSPACE/.n8n-autopilot/feedback"

if [ ! -d "$STORE" ]; then
  echo "[feedback sync] no local feedback store ($STORE) — nothing to sync." >&2
  exit 0
fi

# Hard precheck — no fallback: gh must be installed and authenticated.
if ! command -v gh >/dev/null 2>&1; then
  echo "[feedback sync] ERROR: GitHub CLI 'gh' not installed. Install gh and 'gh auth login', then retry." >&2
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "[feedback sync] ERROR: gh is not authenticated. Run 'gh auth login', then retry." >&2
  exit 1
fi

BODY="$(mktemp)"
COUNT=$(node -e '
const fs=require("fs"), path=require("path");
const store=process.argv[1], bodyPath=process.argv[2];
let recs=[];
for (const f of ["events.ndjson","process.ndjson"]) {
  const p=path.join(store,f); if(!fs.existsSync(p)) continue;
  for (const line of fs.readFileSync(p,"utf8").split("\n")) {
    const s=line.trim(); if(!s) continue;
    try { const r=JSON.parse(s); if (r.synced!==true) recs.push(r); } catch(e){}
  }
}
if (!recs.length) { process.stdout.write("0"); process.exit(0); }
// Human summary: aggregate signal counts + repo labels (no PII).
const agg={}, labels=new Set(); let processN=0;
for (const r of recs) {
  if (r.repoLabel) labels.add(r.repoLabel);
  if (r.kind==="event" && r.signals) for (const [k,v] of Object.entries(r.signals)) agg[k]=(agg[k]||0)+v;
  if (r.kind==="process") processN++;
}
const ranked=Object.entries(agg).sort((a,b)=>b[1]-a[1]);
let md="## Autopilot feedback — "+recs.length+" record(s)\n\n";
md+="- Repos: "+[...labels].join(", ")+"\n";
md+="- Process (interview) records: "+processN+"\n";
md+="- Aggregated friction signals:\n";
for (const [k,v] of ranked) md+="  - `"+k+"`: "+v+"\n";
md+="\n<details><summary>Raw records (NDJSON)</summary>\n\n```ndjson\n";
md+=recs.map(r=>JSON.stringify(r)).join("\n")+"\n```\n</details>\n";
fs.writeFileSync(bodyPath, md);
process.stdout.write(String(recs.length));
' "$STORE" "$BODY" 2>/dev/null || echo "ERR")

if [ "$COUNT" = "ERR" ]; then
  echo "[feedback sync] ERROR: failed to read local records." >&2
  rm -f "$BODY"; exit 1
fi
if [ "$COUNT" = "0" ]; then
  echo "[feedback sync] no unsynced records — nothing to push."
  rm -f "$BODY"; exit 0
fi

# ── Defense-in-depth: deterministic PII allowlist gate before ANY push.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RECORDS_TMP="$(mktemp)"
node -e '
const fs=require("fs"), path=require("path");
const store=process.argv[1], out=process.argv[2];
let recs=[];
for (const f of ["events.ndjson","process.ndjson"]) {
  const p=path.join(store,f); if(!fs.existsSync(p)) continue;
  for (const line of fs.readFileSync(p,"utf8").split("\n")) {
    const s=line.trim(); if(!s) continue;
    try { const r=JSON.parse(s); if (r.synced!==true) recs.push(JSON.stringify(r)); } catch(e){}
  }
}
fs.writeFileSync(out, recs.join("\n")+"\n");
' "$STORE" "$RECORDS_TMP" 2>/dev/null
if ! node "$SCRIPT_DIR/redact-check.js" "$RECORDS_TMP"; then
  echo "[feedback sync] ERROR: redact-check blocked the push (PII / allowlist violation)." >&2
  echo "[feedback sync] Fix the flagged record(s) — re-run the /n8n-autopilot:feedback review so the LLM redaction neutralizes them — then retry sync. Nothing was pushed." >&2
  rm -f "$RECORDS_TMP" "$BODY"; exit 1
fi
rm -f "$RECORDS_TMP"

# Ensure the label exists (idempotent).
gh label create feedback --repo "$REPO" --color B60205 --description "autopilot run feedback" >/dev/null 2>&1 || true

TITLE="feedback: $(node -e 'const fs=require("fs"),p=require("path");const s=process.argv[1];let labels=new Set();for(const f of ["events.ndjson","process.ndjson"]){const fp=p.join(s,f);if(!fs.existsSync(fp))continue;for(const l of fs.readFileSync(fp,"utf8").split("\n")){const t=l.trim();if(!t)continue;try{const r=JSON.parse(t);if(r.synced!==true&&r.repoLabel)labels.add(r.repoLabel);}catch(e){}}}process.stdout.write([...labels].join(",")||"unknown");' "$STORE") ($COUNT records)"

URL=$(gh issue create --repo "$REPO" --label feedback --title "$TITLE" --body-file "$BODY" 2>&1)
RC=$?
rm -f "$BODY"

if [ "$RC" -ne 0 ]; then
  echo "[feedback sync] ERROR: gh issue create failed:" >&2
  echo "$URL" >&2
  exit 1
fi

# Success — mark pushed records synced: move them to synced.ndjson, keep only already-synced in place.
node -e '
const fs=require("fs"), path=require("path");
const store=process.argv[1];
const synced=path.join(store,"synced.ndjson");
for (const f of ["events.ndjson","process.ndjson"]) {
  const p=path.join(store,f); if(!fs.existsSync(p)) continue;
  const keep=[], moved=[];
  for (const line of fs.readFileSync(p,"utf8").split("\n")) {
    const s=line.trim(); if(!s) continue;
    let r; try { r=JSON.parse(s); } catch(e){ continue; }
    if (r.synced===true) keep.push(JSON.stringify(r));
    else { r.synced=true; moved.push(JSON.stringify(r)); }
  }
  fs.writeFileSync(p, keep.length ? keep.join("\n")+"\n" : "");
  if (moved.length) fs.appendFileSync(synced, moved.join("\n")+"\n");
}
' "$STORE" 2>/dev/null || true

echo "[feedback sync] pushed $COUNT record(s) → $URL"
exit 0
