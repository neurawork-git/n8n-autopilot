#!/usr/bin/env node
/**
 * fix-workflows.js — Rewrite stale credential IDs in local `.workflow.ts` files
 *   by joining on credential name against the live n8n instance.
 *
 * Algorithm:
 *   1. Pull live credentials from n8nac (name → { id, type }).
 *   2. Walk workflows/**.workflow.ts and find every
 *        credentials: { <type>: { id: '<oldId>', name: '<credName>' } }
 *      block (id/name order tolerant).
 *   3. For each (type, oldId, credName) triplet:
 *        - If live[credName].id ≠ oldId → schedule rewrite
 *        - If live[credName].type ≠ workflow type → report ambiguity, do NOT rewrite
 *        - If credName not on live instance → report orphan, do NOT rewrite
 *   4. Apply rewrites in-place via targeted regex replace inside each block (never global).
 *
 * Usage:
 *   node fix-workflows.js [--workspace dir] [--dry-run]
 *
 * Exit codes:
 *   0  done (zero or more rewrites applied; orphans reported as warnings)
 *   1  n8nac credential list failed
 *   2  no workflow files found
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const argv = process.argv.slice(2);
const opts = { workspace: process.cwd(), dryRun: false, allProjects: false };
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--workspace')        opts.workspace = argv[++i];
  else if (a === '--dry-run')     opts.dryRun = true;
  else if (a === '--all-projects') opts.allProjects = true;
  else if (a === '-h' || a === '--help') {
    process.stdout.write('Usage: node fix-workflows.js [--workspace dir] [--dry-run] [--all-projects]\n');
    process.exit(0);
  } else {
    console.error(`unknown flag: ${a}`);
    process.exit(2);
  }
}

const workspace = path.resolve(opts.workspace);
const wfDir = path.join(workspace, 'workflows');
if (!fs.existsSync(wfDir)) {
  console.error(`No workflows/ directory at ${wfDir}`);
  process.exit(2);
}

// ── 0. Active project (default scope)
let activeProject = null;
try {
  const ws = JSON.parse(execSync('npx --yes n8nac workspace status --json', {
    cwd: workspace, stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 4 * 1024 * 1024
  }).toString());
  if (ws.activeEnvironment && ws.activeEnvironment.projectId) {
    activeProject = { id: ws.activeEnvironment.projectId, name: ws.activeEnvironment.projectName || '?' };
  }
} catch (e) { /* allowed: workspace not bound surfaces in next step */ }

// ── 1. Live credentials
let raw;
try {
  raw = execSync('npx --yes n8nac credential list --json', {
    cwd: workspace,
    stdio: ['ignore', 'pipe', 'pipe'],
    maxBuffer: 16 * 1024 * 1024
  }).toString();
} catch (e) {
  console.error('npx n8nac credential list --json failed.');
  process.exit(1);
}

let liveByName = {};
let skippedOffProject = 0;
try {
  const parsed = JSON.parse(raw);
  const creds = Array.isArray(parsed) ? parsed : (parsed.credentials || parsed.data || []);
  for (const c of creds) {
    const name = c.name || c.displayName;
    const id   = c.id   || c.credentialId;
    const type = c.type || c.credentialTypeName || c.credentialType;
    if (!name || !id || !type) continue;

    // Determine home project (first shared entry with role=credential:owner)
    const owner = (c.shared || []).find(s => s.role === 'credential:owner') || (c.shared || [])[0];
    const homeProjectId = owner ? owner.id : null;

    // Project-scoping: default = drop creds outside the active project
    if (!opts.allProjects && activeProject && homeProjectId && homeProjectId !== activeProject.id) {
      skippedOffProject++;
      continue;
    }

    if (liveByName[name]) {
      liveByName[name]._conflict = true;
    } else {
      liveByName[name] = { id, type, homeProjectId };
    }
  }
} catch (e) {
  console.error('Could not parse n8nac credential list JSON.');
  process.exit(1);
}

if (activeProject) {
  console.log(`Project scope: ${activeProject.name} (${activeProject.id})${opts.allProjects ? '  [--all-projects: scope ignored]' : ''}`);
  if (!opts.allProjects && skippedOffProject > 0) {
    console.log(`Skipped ${skippedOffProject} credential(s) owned by other projects (use --all-projects to include them).`);
  }
} else {
  console.log('Project scope: NONE (no active project pin) — scanning every visible credential.');
}
console.log('');

// ── 2. Find workflow files
function walk(d, acc = []) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p, acc);
    else if (e.isFile() && e.name.endsWith('.workflow.ts')) acc.push(p);
  }
  return acc;
}
const files = walk(wfDir);
if (files.length === 0) {
  console.error(`No *.workflow.ts files found under ${wfDir}`);
  process.exit(2);
}

// ── 3. Extract credential blocks per file
// Matches:
//   credentials: { <type>: { id: '...', name: '...' } }
//   credentials: { <type>: { name: '...', id: '...' } }
// id/name order tolerant. <type> = first identifier inside the outer { }.
const BLOCK_RE = /credentials:\s*\{\s*([a-zA-Z][a-zA-Z0-9]*)\s*:\s*\{([^{}]+)\}\s*\}/g;

let rewrites = 0;
let orphans = [];
let conflicts = [];

for (const file of files) {
  const rel = path.relative(workspace, file).replace(/\\/g, '/');
  let src = fs.readFileSync(file, 'utf8');
  let changedSrc = src;
  let fileChanges = [];

  // Replace inside each block independently to avoid cross-block collisions.
  changedSrc = src.replace(BLOCK_RE, (match, credType, inner) => {
    const idMatch   = inner.match(/id\s*:\s*['"]([^'"]+)['"]/);
    const nameMatch = inner.match(/name\s*:\s*['"]([^'"]+)['"]/);
    if (!idMatch || !nameMatch) return match; // unparseable, leave alone

    const oldId    = idMatch[1];
    const credName = nameMatch[1];
    const live     = liveByName[credName];

    if (!live) {
      orphans.push({ file: rel, credType, credName });
      return match;
    }
    if (live._conflict) {
      conflicts.push({ file: rel, credType, credName, reason: 'duplicate name on instance' });
      return match;
    }
    if (live.type !== credType) {
      conflicts.push({ file: rel, credType, credName, liveType: live.type, reason: 'type mismatch' });
      return match;
    }
    if (live.id === oldId) {
      return match; // already correct, no rewrite needed
    }

    // Replace ONLY the id value inside this block.
    const rewritten = match.replace(
      /(id\s*:\s*['"])[^'"]+(['"])/,
      `$1${live.id}$2`
    );
    fileChanges.push({ credType, oldId, newId: live.id });
    return rewritten;
  });

  if (fileChanges.length > 0 && changedSrc !== src) {
    if (!opts.dryRun) {
      fs.writeFileSync(file, changedSrc);
    }
    for (const ch of fileChanges) {
      rewrites++;
      console.log(`  ${opts.dryRun ? 'WOULD UPDATE' : 'UPDATED'}  ${rel}  ${ch.credType}  ${ch.oldId} → ${ch.newId}`);
    }
  }
}

console.log('');
if (rewrites === 0) {
  console.log('No stale credential IDs found.');
} else {
  console.log(`${opts.dryRun ? 'Would update' : 'Updated'} ${rewrites} credential reference(s).`);
}

if (orphans.length > 0) {
  console.log('');
  console.log(`Orphans (credential name not found on live instance — manual action required):`);
  for (const o of orphans) {
    console.log(`  ${o.file}  ${o.credType}  name='${o.credName}'`);
  }
  console.log(`  → Create the credential on the instance or remove the reference.`);
}

if (conflicts.length > 0) {
  console.log('');
  console.log(`Conflicts (not auto-fixed — user must decide):`);
  for (const c of conflicts) {
    if (c.reason === 'type mismatch') {
      console.log(`  ${c.file}  workflow=${c.credType}  live=${c.liveType}  name='${c.credName}'  (TYPE MISMATCH)`);
    } else {
      console.log(`  ${c.file}  ${c.credType}  name='${c.credName}'  (${c.reason})`);
    }
  }
}
