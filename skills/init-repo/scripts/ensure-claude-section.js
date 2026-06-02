#!/usr/bin/env node
// ensure-claude-section.js — idempotently anchor the n8n-autopilot section into a repo's CLAUDE.md.
//
//   node ensure-claude-section.js [--workspace <dir>] [--templates <dir>] [--force]
//
// Behaviour (idempotent, re-run safe):
//   - no CLAUDE.md            → create it with the section.
//   - has START/END markers   → replace the block between them (in-place update).
//   - full autopilot template → SKIP (the full template already covers it) unless --force.
//   - foreign CLAUDE.md       → append the marked section at the end.
//
// Markers: <!-- n8n-autopilot:start --> ... <!-- n8n-autopilot:end -->
// Used by init-repo.sh and runnable standalone on any existing repo.

const fs = require("fs");
const path = require("path");

function arg(name, def) {
  const i = process.argv.indexOf(name);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : def;
}
const FORCE = process.argv.includes("--force");

const workspace = path.resolve(arg("--workspace", process.cwd()));
const scriptDir = __dirname;
const templatesDir = path.resolve(arg("--templates", path.join(scriptDir, "..", "assets", "templates")));
const sectionPath = path.join(templatesDir, "CLAUDE-section.md");
const target = path.join(workspace, "CLAUDE.md");

const START = "<!-- n8n-autopilot:start -->";
const END = "<!-- n8n-autopilot:end -->";

if (!fs.existsSync(sectionPath)) {
  console.error("ensure-claude-section: section template not found at " + sectionPath);
  process.exit(1);
}
let section = fs.readFileSync(sectionPath, "utf8").trim();
section = section.replace(/\{\{REPO_NAME\}\}/g, path.basename(workspace));

// Case 1: no CLAUDE.md → create with the section.
if (!fs.existsSync(target)) {
  fs.writeFileSync(target, section + "\n");
  console.log("CREATE " + target + " (with n8n-autopilot section)");
  process.exit(0);
}

let content = fs.readFileSync(target, "utf8");

// Case 2: markers present → replace the block (idempotent update).
const si = content.indexOf(START);
const ei = content.indexOf(END);
if (si !== -1 && ei !== -1 && ei > si) {
  const before = content.slice(0, si);
  const after = content.slice(ei + END.length);
  const updated = before + section + after;
  if (updated === content) {
    console.log("OK     " + target + " (section already current)");
  } else {
    fs.writeFileSync(target, updated);
    console.log("UPDATE " + target + " (refreshed n8n-autopilot section)");
  }
  process.exit(0);
}

// Case 3: full autopilot template already present (sentinel) → skip unless --force.
if (!FORCE && /uses the \*\*n8n-autopilot plugin\*\*/.test(content)) {
  console.log("SKIP   " + target + " (already a full n8n-autopilot CLAUDE.md; use --force to add the marked section anyway)");
  process.exit(0);
}

// Case 4: foreign CLAUDE.md → append the marked section.
const sep = content.endsWith("\n") ? "\n" : "\n\n";
fs.writeFileSync(target, content + sep + section + "\n");
console.log("APPEND " + target + " (added n8n-autopilot section to existing CLAUDE.md)");
process.exit(0);
