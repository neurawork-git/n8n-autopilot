#!/usr/bin/env node
/**
 * search.js — Find credentials on the active n8n instance by name pattern,
 *   scoped to a project. Default scope = workspace-pinned project.
 *
 * Usage:
 *   node search.js <name-pattern> [--type <credType>] [--project <name|id|all>] [--exact] [--json]
 *
 * Exit codes:
 *   0  matches found and printed
 *   1  workspace not bound / CLI failure / args invalid
 *   2  no matches in selected scope
 */

const { execSync } = require('child_process');

// ── Args
const argv = process.argv.slice(2);
const opts = { pattern: '', type: null, project: null, exact: false, json: false };
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--type')         opts.type    = argv[++i];
  else if (a === '--project') opts.project = argv[++i];
  else if (a === '--exact')   opts.exact   = true;
  else if (a === '--json')    opts.json    = true;
  else if (a === '-h' || a === '--help') {
    process.stdout.write('Usage: search.js <name-pattern> [--type T] [--project N|all] [--exact] [--json]\n');
    process.exit(0);
  } else if (!opts.pattern) {
    opts.pattern = a;
  } else {
    // Treat extra positional as pattern continuation (allows unquoted multi-word search)
    opts.pattern += ' ' + a;
  }
}

const pattern = opts.pattern.trim();
if (!pattern && !opts.type) {
  console.error('ERROR: provide a name pattern OR --type. Example: search.js stella --type dropboxOAuth2Api');
  process.exit(1);
}

// ── Workspace status → active project
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

// ── Resolve --project flag
let scopeMode = 'active';   // 'active' | 'all' | 'explicit'
let scopeFilter = null;     // when 'explicit': { id?, name? }
if (opts.project) {
  if (opts.project === 'all') {
    scopeMode = 'all';
  } else {
    scopeMode = 'explicit';
    scopeFilter = { id: opts.project, name: opts.project };
  }
}

// ── Fetch credentials
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

// ── Filter
const needle = pattern.toLowerCase();
function matchName(name) {
  if (!pattern) return true;
  const n = (name || '').toLowerCase();
  return opts.exact ? n === needle : n.includes(needle);
}
function matchType(type) {
  if (!opts.type) return true;
  return type === opts.type;
}
function ownerOf(c) {
  // First entry in shared[] with role === credential:owner is the home project
  const owner = (c.shared || []).find(s => s.role === 'credential:owner') || (c.shared || [])[0];
  return owner ? { id: owner.id, name: owner.name, role: owner.role || '?' } : null;
}
function matchProject(owner) {
  if (scopeMode === 'all') return true;
  if (!owner) return scopeMode === 'active' && !activeProject;
  if (scopeMode === 'active') {
    return activeProject && owner.id === activeProject.id;
  }
  // explicit
  return owner.id === scopeFilter.id || owner.name === scopeFilter.name;
}

const matchesByProject = {};      // projectName → [creds]
const offScopeCounts = {};        // projectName → count (only relevant in 'active' mode)

for (const c of creds) {
  const name = c.name || c.displayName || '';
  const type = c.type || c.credentialTypeName || '?';
  if (!matchName(name) || !matchType(type)) continue;
  const owner = ownerOf(c);
  const projKey = owner ? `${owner.name} (${owner.id})` : '(unowned)';
  if (matchProject(owner)) {
    (matchesByProject[projKey] ||= []).push({ id: c.id, name, type, ownerRole: owner ? owner.role : '?' });
  } else if (scopeMode === 'active') {
    offScopeCounts[projKey] = (offScopeCounts[projKey] || 0) + 1;
  }
}

// ── JSON output mode
if (opts.json) {
  process.stdout.write(JSON.stringify({
    activeProject,
    scope: { mode: scopeMode, filter: scopeFilter },
    matchesByProject,
    offScopeCounts
  }, null, 2) + '\n');
  const total = Object.values(matchesByProject).reduce((a, b) => a + b.length, 0);
  process.exit(total === 0 ? 2 : 0);
}

// ── Human output
console.log('');
if (activeProject) {
  console.log(`Active project (workspace pin): ${activeProject.name} (${activeProject.id})`);
} else {
  console.log('Active project: NONE (workspace has no project pin — set via `npx n8nac workspace set-project --project-name <name>`)');
}
console.log(`Scope: ${scopeMode}${scopeFilter ? ' (' + (scopeFilter.id || scopeFilter.name) + ')' : ''}    Pattern: "${pattern || '*'}"${opts.type ? '    Type: ' + opts.type : ''}${opts.exact ? '    (exact)' : ''}`);
console.log('');

const totalMatches = Object.values(matchesByProject).reduce((a, b) => a + b.length, 0);
if (totalMatches === 0) {
  console.log('No matches.');
  const offTotal = Object.values(offScopeCounts).reduce((a, b) => a + b, 0);
  if (offTotal > 0) {
    console.log('');
    console.log(`Matches exist in other projects (use --project all to see):`);
    for (const [proj, n] of Object.entries(offScopeCounts)) {
      console.log(`  ${proj}: ${n}`);
    }
  }
  process.exit(2);
}

for (const [proj, list] of Object.entries(matchesByProject)) {
  console.log(`── Project: ${proj} ── ${list.length} match(es)`);
  const w = {
    id:   Math.max(2, ...list.map(r => r.id.length)),
    type: Math.max(4, ...list.map(r => r.type.length)),
    name: Math.max(4, ...list.map(r => r.name.length)),
  };
  const pad = (s, n) => String(s).padEnd(n);
  console.log(`  ${pad('ID', w.id)}  ${pad('Type', w.type)}  ${pad('Name', w.name)}  Owner role`);
  console.log(`  ${'-'.repeat(w.id)}  ${'-'.repeat(w.type)}  ${'-'.repeat(w.name)}  ${'-'.repeat(16)}`);
  for (const r of list) {
    console.log(`  ${pad(r.id, w.id)}  ${pad(r.type, w.type)}  ${pad(r.name, w.name)}  ${r.ownerRole}`);
  }
  console.log('');
  console.log('  TypeScript snippet(s):');
  for (const r of list) {
    console.log(`    credentials: { ${r.type}: { id: "${r.id}", name: "${r.name}" } }`);
  }
  console.log('');
}

const offTotal = Object.values(offScopeCounts).reduce((a, b) => a + b, 0);
if (scopeMode === 'active' && offTotal > 0) {
  console.log(`Other projects with "${pattern}" matches (hidden — use --project all to see):`);
  for (const [proj, n] of Object.entries(offScopeCounts)) {
    console.log(`  ${proj}: ${n}`);
  }
}

process.exit(0);
