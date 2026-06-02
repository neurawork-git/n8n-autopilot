#!/usr/bin/env node
// latest-transcript.js — resolve the newest Claude Code session transcript (.jsonl) for a repo.
// Used by the /n8n-autopilot:feedback review flow to find the session to review.
//
//   node latest-transcript.js [--workspace <dir>] [--print-path-only]
//
// Claude Code stores transcripts at ~/.claude/projects/<encoded-cwd>/<session-id>.jsonl where
// <encoded-cwd> = the absolute cwd with every / \ : replaced by '-'. Prints the newest match.

const fs = require("fs");
const path = require("path");
const os = require("os");

function arg(name, def) {
  const i = process.argv.indexOf(name);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : def;
}

const workspace = path.resolve(arg("--workspace", process.cwd()));
const encoded = workspace.replace(/[\\/:]/g, "-");
const dir = path.join(os.homedir(), ".claude", "projects", encoded);

if (!fs.existsSync(dir)) {
  console.error("latest-transcript: no transcript dir for workspace (" + dir + ")");
  process.exit(1);
}

const files = fs.readdirSync(dir)
  .filter(f => f.endsWith(".jsonl"))
  .map(f => { const p = path.join(dir, f); return { p, mtime: fs.statSync(p).mtimeMs }; })
  .sort((a, b) => b.mtime - a.mtime);

if (!files.length) {
  console.error("latest-transcript: no .jsonl transcripts in " + dir);
  process.exit(1);
}

process.stdout.write(files[0].p);
