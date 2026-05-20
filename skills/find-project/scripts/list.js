#!/usr/bin/env node
/**
 * list.js — Enumerate n8n projects visible on the active instance.
 *
 * n8n public API does not expose /projects outside Enterprise; we derive the
 * project set from credential ownership (`credential list --json` returns
 * `shared[].name` and `shared[].id` for each cred).
 *
 * Usage:
 *   node list.js [--name <filter>] [--json]
 *
 * Exit codes:
 *   0  printed
 *   1  workspace not bound / CLI failure
 */

const { execSync } = require('child_process');

const argv = process.argv.slice(2);
const opts = { name: null, json: false };
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--name')      opts.name = argv[++i];
  else if (a === '--json') opts.json = true;
  else if (a === '-h' || a === '--help') {
    process.stdout.write('Usage: list.js [--name filter] [--json]\n');
    process.exit(0);
  }
}

let ws;
try {
  ws = JSON.parse(execSync('npx --yes n8nac workspace status --json', {
    stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 4 * 1024 * 1024
  }).toString());
} catch (e) {
  console.error('ERROR: workspace not bound. Run: npx n8nac setup --mode connect-existing');
  process.exit(1);
}

const activeProject = ws.activeEnvironment && ws.activeEnvironment.projectId
  ? { id: ws.activeEnvironment.projectId, name: ws.activeEnvironment.projectName || '?' }
  : null;

const target = (ws.environmentTargets || []).find(t => t.id === (ws.activeEnvironment && ws.activeEnvironment.environmentTargetId)) || (ws.environmentTargets || [])[0];
const instanceUrl = target ? target.url : '(unknown)';

let creds;
try {
  const raw = execSync('npx --yes n8nac credential list --json', {
    stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 16 * 1024 * 1024
  }).toString();
  const parsed = JSON.parse(raw);
  creds = Array.isArray(parsed) ? parsed : (parsed.credentials || parsed.data || []);
} catch (e) {
  console.error('ERROR: npx n8nac credential list --json failed.');
  process.exit(1);
}

const projects = {};   // id → { id, name, credentialCount }
for (const c of creds) {
  const owner = (c.shared || []).find(s => s.role === 'credential:owner') || (c.shared || [])[0];
  if (!owner) continue;
  const key = owner.id;
  if (!projects[key]) projects[key] = { id: owner.id, name: owner.name || '?', credentialCount: 0 };
  projects[key].credentialCount++;
}

// Ensure the active project shows up even if it owns 0 credentials
if (activeProject && !projects[activeProject.id]) {
  projects[activeProject.id] = { id: activeProject.id, name: activeProject.name, credentialCount: 0 };
}

let rows = Object.values(projects);
if (opts.name) {
  const needle = opts.name.toLowerCase();
  rows = rows.filter(r => r.name.toLowerCase().includes(needle));
}
rows.sort((a, b) => a.name.localeCompare(b.name));

if (opts.json) {
  process.stdout.write(JSON.stringify({ instanceUrl, activeProject, projects: rows }, null, 2) + '\n');
  process.exit(0);
}

console.log('');
if (activeProject) {
  console.log(`Active project pin: ${activeProject.name} (${activeProject.id})`);
} else {
  console.log('Active project pin: NONE');
}
console.log('');
console.log(`Projects visible on ${instanceUrl}:`);
console.log('');

if (rows.length === 0) {
  console.log('  (no projects derivable from credentials — instance may have no credentials yet)');
} else {
  const w = {
    id:   Math.max(2, ...rows.map(r => r.id.length)),
    name: Math.max(4, ...rows.map(r => r.name.length)),
  };
  const pad = (s, n) => String(s).padEnd(n);
  console.log(`  ${pad('ID', w.id)}  ${pad('Name', w.name)}  Credentials  Active pin?`);
  console.log(`  ${'-'.repeat(w.id)}  ${'-'.repeat(w.name)}  -----------  -----------`);
  for (const r of rows) {
    const activeMark = activeProject && r.id === activeProject.id ? '← active' : '';
    console.log(`  ${pad(r.id, w.id)}  ${pad(r.name, w.name)}  ${String(r.credentialCount).padEnd(11)}  ${activeMark}`);
  }
}

console.log('');
console.log('To switch the workspace to a different project:');
console.log('  npx n8nac workspace set-project --project-name "<Name>"');
console.log('  npx n8nac workspace set-project --project-id "<ID>"');
console.log('');
console.log('After switching, re-run /n8n-autopilot:check-mcps to verify the new scope.');
