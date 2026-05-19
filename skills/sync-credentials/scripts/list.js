#!/usr/bin/env node
/**
 * list.js — Fetch credentials from the live n8n instance (via `npx n8nac credential list --json`)
 *   and print: (1) a human-readable table, (2) ready-to-paste TypeScript snippets.
 *
 * Usage:
 *   node list.js [--workspace dir]
 *
 * Exit codes:
 *   0  printed successfully
 *   1  n8nac CLI failed or returned no credentials
 */

const { execSync } = require('child_process');

const workspace = (() => {
  const i = process.argv.indexOf('--workspace');
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : process.cwd();
})();

let raw;
try {
  raw = execSync('npx --yes n8nac credential list --json', {
    cwd: workspace,
    stdio: ['ignore', 'pipe', 'pipe'],
    maxBuffer: 16 * 1024 * 1024
  }).toString();
} catch (e) {
  console.error('npx n8nac credential list --json failed.');
  console.error('  Workspace bound? Run: npx n8nac workspace status --json');
  process.exit(1);
}

let creds;
try {
  const parsed = JSON.parse(raw);
  creds = Array.isArray(parsed) ? parsed : (parsed.credentials || parsed.data || []);
} catch (e) {
  console.error('Could not parse n8nac credential list JSON output.');
  process.exit(1);
}

if (creds.length === 0) {
  console.log('No credentials configured on the active n8n instance.');
  console.log('Create one in the n8n UI (or `npx n8nac credential create --type <type> --name <name> --file cred.json`).');
  process.exit(0);
}

// Normalize: each entry should have { id, name, type }
const rows = creds.map(c => ({
  type: c.type || c.credentialTypeName || c.credentialType || '?',
  id:   c.id   || c.credentialId       || '?',
  name: c.name || c.displayName        || '?'
}));

// ── Table
const colWidth = (key) => Math.max(key.length, ...rows.map(r => String(r[key]).length));
const w = { type: colWidth('type'), id: colWidth('id'), name: colWidth('name') };
const pad = (s, n) => String(s).padEnd(n);

console.log(`${pad('Credential Type', w.type)}  ${pad('ID', w.id)}  Name`);
console.log(`${'-'.repeat(w.type)}  ${'-'.repeat(w.id)}  ${'-'.repeat(w.name)}`);
for (const r of rows) {
  console.log(`${pad(r.type, w.type)}  ${pad(r.id, w.id)}  ${r.name}`);
}

// ── TypeScript snippets
console.log('');
console.log('Ready-to-paste TypeScript snippets:');
console.log('');
for (const r of rows) {
  console.log(`  credentials: { ${r.type}: { id: "${r.id}", name: "${r.name}" } }`);
}
