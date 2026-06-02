#!/usr/bin/env node
// redact-check.js — deterministic PII allowlist gate for feedback records before central push.
// Defense-in-depth on top of the LLM redaction done in the /n8n-autopilot:feedback review flow.
//
//   node redact-check.js <ndjsonFile>        # validates every record; exit 0 = clean, 2 = blocked
//   cat records | node redact-check.js -      # stdin form
//
// BLOCKS (exit 2) and reports the offending record+field if:
//   - any unknown top-level key is present (allowlist violation), or
//   - any free-text field matches a PII denylist pattern.
// Customer names can be added via env N8N_AUTOPILOT_PII_NAMES="Name1,Name2" (comma-separated).
// Deterministic PII allowlist gate.

const fs = require("fs");

const ALLOWED_KEYS = new Set([
  "kind", "schemaVersion", "sessionId", "ts", "endReason", "n8nacVersion",
  "repoLabel", "signals", "answers", "freeText", "insights", "synced"
]);
const ALLOWED_SIGNALS = new Set([
  "push_gate_block", "validate_fail", "credential_missing", "action_required",
  "mcptrigger_detour", "non_http_test", "conflict_resolve", "curl_block",
  "schema_gap", "tool_error", "archived_rejected", "memory_oom", "continue_on_fail",
  // file-level design metrics produced by the review skill:
  "code_nodes", "native_conditional", "missing_descriptions", "overlapping_nodes"
]);

// PII denylist — deterministic patterns that must never leave the machine in free text.
const PII = [
  { name: "email",        re: /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/ },
  { name: "abs-path-win", re: /[A-Za-z]:\\(?:[^\\\s"']+\\?)+/ },
  { name: "abs-path-nix", re: /(?:\/Users\/|\/home\/|\/mnt\/|\/var\/)[^\s"']+/ },
  { name: "url-host",     re: /https?:\/\/[^\s"']+/ },
  { name: "long-digits",  re: /\b\d{12,}\b/ },              // IBAN/account/id runs
  { name: "iban",         re: /\b[A-Z]{2}\d{2}[A-Z0-9]{10,30}\b/ },
  { name: "bearer/token", re: /(?:bearer|api[_-]?key|token|secret)\s*[:=]\s*\S{8,}/i },
  { name: "jwt",          re: /eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/ }
];
const NAMES = (process.env.N8N_AUTOPILOT_PII_NAMES || "")
  .split(",").map(s => s.trim()).filter(Boolean);

function scanText(s) {
  if (typeof s !== "string" || !s) return null;
  for (const p of PII) if (p.re.test(s)) return p.name;
  for (const n of NAMES) if (new RegExp("\\b" + n.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "\\b", "i").test(s)) return "customer-name:" + n;
  return null;
}

function freeTextFields(rec) {
  const out = [];
  if (typeof rec.freeText === "string") out.push(["freeText", rec.freeText]);
  if (rec.answers && typeof rec.answers === "object")
    for (const [k, v] of Object.entries(rec.answers)) if (typeof v === "string") out.push(["answers." + k, v]);
  if (rec.insights && typeof rec.insights === "object")
    for (const [k, v] of Object.entries(rec.insights)) if (typeof v === "string") out.push(["insights." + k, v]);
  return out;
}

const src = process.argv[2];
let raw = "";
try {
  raw = src && src !== "-" ? fs.readFileSync(src, "utf8") : fs.readFileSync(0, "utf8");
} catch (e) {
  console.error("redact-check: cannot read input — " + e.message);
  process.exit(1);
}

const violations = [];
let n = 0;
for (const line of raw.split("\n")) {
  const s = line.trim();
  if (!s) continue;
  n++;
  let rec;
  try { rec = JSON.parse(s); } catch (e) { violations.push(`record ${n}: invalid JSON`); continue; }

  for (const k of Object.keys(rec))
    if (!ALLOWED_KEYS.has(k)) violations.push(`record ${n}: unknown key '${k}' (allowlist violation)`);

  if (rec.signals && typeof rec.signals === "object")
    for (const [k, v] of Object.entries(rec.signals)) {
      if (!ALLOWED_SIGNALS.has(k)) violations.push(`record ${n}: unknown signal '${k}'`);
      if (typeof v !== "number") violations.push(`record ${n}: signal '${k}' is not a number`);
    }

  if (rec.repoLabel != null && !/^[A-Za-z0-9._-]+$/.test(String(rec.repoLabel)))
    violations.push(`record ${n}: repoLabel '${rec.repoLabel}' is not a bare basename (path leak risk)`);

  for (const [field, val] of freeTextFields(rec)) {
    const hit = scanText(val);
    if (hit) violations.push(`record ${n}: field '${field}' matches PII pattern [${hit}]`);
  }
}

if (violations.length) {
  console.error("redact-check: BLOCKED — " + violations.length + " issue(s):");
  for (const v of violations) console.error("  - " + v);
  process.exit(2);
}
console.log("redact-check: OK — " + n + " record(s) clean, safe to push.");
process.exit(0);
