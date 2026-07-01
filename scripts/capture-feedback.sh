#!/usr/bin/env bash
# capture-feedback.sh — SessionEnd auto-capture for the autopilot feedback loop.
#
# Reads the SessionEnd hook JSON on STDIN ({session_id, transcript_path, reason, cwd}),
# extracts NON-PII friction signal COUNTS from the transcript (anchored grep against a frozen
# signal taxonomy), and appends ONE kind:"event" NDJSON record to
# <cwd>/.n8n-autopilot/feedback/events.ndjson.
#
# Fire-and-forget: SessionEnd output is ignored by Claude/the user. NEVER blocks, ALWAYS exit 0.
# Captures ONLY structured counts — never transcript text, workflow content, credentials, or paths.
#
# Called by: hooks/hooks.json SessionEnd.
# NB: PreToolUse hooks get input via $CLAUDE_TOOL_INPUT / $1; SessionEnd gets JSON on STDIN.

# Deliberately NO `set -e` — must never disrupt session shutdown.
INPUT="$(cat 2>/dev/null || true)"
[ -z "$INPUT" ] && exit 0

printf '%s' "$INPUT" | node -e '
let d=""; process.stdin.on("data",c=>d+=c); process.stdin.on("end",()=>{
  try {
    const fs=require("fs"), path=require("path");
    const hook=JSON.parse(d);
    const cwd = hook.cwd || process.cwd();
    const tp  = hook.transcript_path || "";
    // Transcript missing/unreadable -> exit silently (cannot compute signals).
    if (!tp || !fs.existsSync(tp)) process.exit(0);
    // Only scan real conversation turns. Skill-listing + SessionStart-hook injections arrive
    // as type:"attachment"/"system" lines and contain the taxonomy keywords verbatim
    // (mcpTrigger, pull-schemas, non-HTTP, --include-data) -> pure false positives. Filter them out.
    let text="";
    try {
      const raw = fs.readFileSync(tp,"utf8");
      for (const line of raw.split("\n")) {
        if (!line) continue;
        let o; try { o = JSON.parse(line); } catch(e) { continue; }
        if (o.type !== "user" && o.type !== "assistant") continue;
        text += JSON.stringify(o.message || "") + "\n";
      }
    } catch(e) { process.exit(0); }
    // ponytail: residual within-line dup (same text in content+stdout) left uncounted;
    // fix per-field extraction only if a signal noise floor proves it matters.

    // Anchored signal heuristics — frozen taxonomy from real production-run analysis.
    // Bare keywords ("BLOCKED","CONFLICT") are AVOIDED: they collide with n8n node JSON
    // ("blockedBy") and SQL ("ON CONFLICT"). See baseline calibration L1/L4.
    const PAT = {
      push_gate_block:    /\[push-gate\]|push\s{0,3}blocked/gi,
      validate_fail:      /skills validate|validation failed|✖|invalid workflow/gi,
      credential_missing: /credential.{0,40}(missing|not found|does not exist|stale)/gi,
      action_required:    /AUTOPILOT_ACTION_REQUIRED/gi,
      mcptrigger_detour:  /mcptrigger|must.{0,10}publish|click .?publish/gi,
      non_http_test:      /execute workflow.{0,10}button|non-http|manual.{0,10}trigger|--include-data/gi,
      conflict_resolve:   /DIVERGED|MODIFIED_BOTH|n8nac resolve|REMOTE_ONLY|keep-current|local-wins|conflict resolved for|status.{0,3}conflict/gi,
      curl_block:         /BLOCKED:.{0,40}(curl|wget)|never call n8n rest/gi,
      schema_gap:         /pull-schemas|no cached schema|schema.{0,20}not found|node schema/gi,
      tool_error:         /"is_error":true|tool_use_error/gi,
      archived_rejected:  /archived.{0,25}(read-only|rejected|cannot|not allowed)|unarchive/gi,
      // Design-quality signals (transcript-detectable).
      // memory_oom: anchored to real OOM events, NOT the word "cheap" (template-cost noise).
      memory_oom:         /out of memory|\bOOM\b|heap.{0,12}(spike|limit|error|out)|crashed.{0,8}pod|JavaScript heap/gi,
      continue_on_fail:   /continueOnFail["\x27\s:]{0,4}true|onError["\x27\s:]{0,4}["\x27]?continue/gi
    };
    const signals={};
    for (const [k,re] of Object.entries(PAT)) {
      const m = text.match(re);
      if (m && m.length) signals[k] = m.length;   // omit zero-count classes
    }

    // n8nac version — read locally (no spawn): consumer node_modules first, else "".
    let n8nacVersion="";
    try {
      const pj = path.join(cwd,"node_modules","n8nac","package.json");
      if (fs.existsSync(pj)) n8nacVersion = JSON.parse(fs.readFileSync(pj,"utf8")).version || "";
    } catch(e) {}

    const rec = {
      kind: "event",
      schemaVersion: 1,
      sessionId: hook.session_id || "",
      ts: new Date().toISOString(),
      endReason: hook.reason || "other",
      n8nacVersion,
      repoLabel: path.basename(cwd),   // basename ONLY — no path leak
      signals,                          // {} if zero friction this session
      synced: false
    };

    const store = path.join(cwd,".n8n-autopilot","feedback");
    fs.mkdirSync(store,{recursive:true});
    const file = path.join(store,"events.ndjson");
    // One UNSYNCED event per session, last-write-wins: a resumed session re-scans a superset
    // of the transcript, so the later SessionEnd counts already include the earlier ones.
    // Drop any prior unsynced event for this session; keep synced history intact.
    let keep = [];
    try {
      keep = fs.readFileSync(file,"utf8").split("\n").filter(Boolean).filter(l => {
        try { const p = JSON.parse(l); return p.sessionId !== rec.sessionId || p.synced === true; }
        catch(e) { return true; }
      });
    } catch(e) {}
    keep.push(JSON.stringify(rec));
    fs.writeFileSync(file, keep.join("\n")+"\n");
  } catch(e) { /* fire-and-forget: never disrupt shutdown */ }
  process.exit(0);
});
' 2>/dev/null || true
exit 0
