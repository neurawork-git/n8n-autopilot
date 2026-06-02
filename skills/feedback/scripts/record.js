#!/usr/bin/env node
// record.js — append one feedback record to the local store.
// Invoked by the /n8n-autopilot:feedback skill:
//   node "$CLAUDE_PLUGIN_ROOT/skills/feedback/scripts/record.js" '<json>' [--workspace <dir>]
// where <json> = {"kind":"process|insight", "answers":{...}, "freeText":"...",
//                 "insights":{...}, "signals":{...}}  (already PII-redacted by the caller).
// Defaults to kind "process". Allowlist + gate: redact-check.js.

const fs = require("fs");
const path = require("path");

function arg(name, def) {
  const i = process.argv.indexOf(name);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : def;
}

const workspace = arg("--workspace", process.cwd());

// First positional (non-flag) arg = answers JSON.
const positional = process.argv.slice(2).find(a => !a.startsWith("--") &&
  process.argv[process.argv.indexOf(a) - 1] !== "--workspace");

let payload = {};
if (positional) {
  try { payload = JSON.parse(positional); }
  catch (e) {
    console.error("record.js: invalid JSON payload — " + e.message);
    process.exit(1);
  }
}

const kind = payload.kind === "insight" ? "insight" : "process";
const rec = {
  kind,
  schemaVersion: 1,
  sessionId: process.env.CLAUDE_SESSION_ID || "manual",
  ts: new Date().toISOString(),
  repoLabel: path.basename(workspace),
  synced: false
};
if (payload.answers && typeof payload.answers === "object") rec.answers = payload.answers;
if (typeof payload.freeText === "string") rec.freeText = payload.freeText;
if (payload.insights && typeof payload.insights === "object") rec.insights = payload.insights;
if (payload.signals && typeof payload.signals === "object") rec.signals = payload.signals;

const store = path.join(workspace, ".n8n-autopilot", "feedback");
fs.mkdirSync(store, { recursive: true });
// process records → process.ndjson; insight records → process.ndjson too (both are "review" output,
// distinct from auto-captured events.ndjson). sync + redact-check read both ndjson files.
const target = path.join(store, "process.ndjson");
fs.appendFileSync(target, JSON.stringify(rec) + "\n");
console.log("recorded " + kind + " feedback to " + target);
