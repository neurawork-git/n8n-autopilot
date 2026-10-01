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
    // Also wired to PreCompact + SessionStart, because SessionEnd only fires on a CLEAN end
    // (reason: clear / prompt_input_exit / other). Long sessions that get resumed or left open —
    // exactly the ones with the most friction — never fired it: measured gap 2026-07-01..07-27
    // with zero events despite multi-hour n8nac sessions. Skip the SessionStart flavors that
    // carry no prior transcript (startup / clear); resume + compact DO carry one.
    if (hook.source === "startup" || hook.source === "clear") process.exit(0);
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

    // n8nac version — read locally (no spawn): consumer node_modules first, then the npx cache.
    // Everyone runs n8nac via npx, so node_modules never exists -> every event before 5.3.0
    // carried n8nacVersion:"" (versionless telemetry). ponytail: scan the cache instead of
    // spawning `n8nac --version` (~2s inside a fire-and-forget shutdown hook).
    let n8nacVersion="";
    const readVer = (pj) => { try { return fs.existsSync(pj) ? (JSON.parse(fs.readFileSync(pj,"utf8")).version || "") : "" } catch(e) { return "" } };
    n8nacVersion = readVer(path.join(cwd,"node_modules","n8nac","package.json"));
    if (!n8nacVersion) {
      const home = process.env.HOME || process.env.USERPROFILE || "";
      const roots = [
        process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA,"npm-cache","_npx") : "",
        home ? path.join(home,".npm","_npx") : "",
      ].filter(Boolean);
      const newer = (a,b) => { const A=String(a).split("."), B=String(b).split(".");
        for (let i=0;i<3;i++) { const x=+A[i]||0, y=+B[i]||0; if (x!==y) return x>y } return false };
      for (const root of roots) {
        try {
          if (!fs.existsSync(root)) continue;
          for (const dir of fs.readdirSync(root)) {
            const v = readVer(path.join(root,dir,"node_modules","n8nac","package.json"));
            if (v && (!n8nacVersion || newer(v,n8nacVersion))) n8nacVersion = v;
          }
        } catch(e) {}
      }
    }

    const rec = {
      kind: "event",
      schemaVersion: 1,
      sessionId: hook.session_id || "",
      ts: new Date().toISOString(),
      // Which hook captured this: SessionEnd carries `reason`, SessionStart `source`,
      // PreCompact `trigger`. Keeping it visible makes a capture-coverage gap measurable.
      endReason: hook.reason || (hook.source ? `start:${hook.source}` : hook.trigger ? `precompact:${hook.trigger}` : "other"),
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
