#!/usr/bin/env node
/**
 * fetch-pkg.js — Extract n8n node schemas directly from a published npm package.
 * Use when `npx n8nac skills node-info` does not know the node (Stage 2 fallback).
 *
 * Writes one JSON per node class found in the package to:
 *   schemas/nodes/<pkg-name>.<node-name>.json           (unscoped packages)
 *   schemas/nodes/<scope>/<pkg-name>.<node-name>.json   (scoped packages)
 *
 * Usage:
 *   node fetch-pkg.js <npm-package-name> [workspace-root]
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const os = require('os');

const pkg = process.argv[2];
const workspaceRoot = process.argv[3] || process.cwd();

if (!pkg) {
  console.error('Usage: node fetch-pkg.js <npm-package-name> [workspace-root]');
  process.exit(2);
}

const outBase = path.join(workspaceRoot, 'schemas', 'nodes');
fs.mkdirSync(outBase, { recursive: true });

// Install pkg + n8n-workflow peer dep into a fresh temp dir so we don't pollute the workspace.
const runnerDir = fs.mkdtempSync(path.join(os.tmpdir(), 'n8nac-schema-'));
fs.writeFileSync(
  path.join(runnerDir, 'package.json'),
  JSON.stringify({
    name: 'n8nac-schema-runner',
    version: '0.0.0',
    private: true,
    dependencies: { [pkg]: '*', 'n8n-workflow': '*' }
  })
);

try {
  execSync('npm install --silent --no-audit --no-fund', { cwd: runnerDir, stdio: ['ignore', 'ignore', 'inherit'] });
} catch (e) {
  console.error(`npm install for ${pkg} failed`);
  process.exit(3);
}

const pkgRoot = path.join(runnerDir, 'node_modules', pkg);
let pkgJson;
try {
  pkgJson = JSON.parse(fs.readFileSync(path.join(pkgRoot, 'package.json'), 'utf8'));
} catch (e) {
  console.error(`Could not read package.json of ${pkg}: ${e.message}`);
  process.exit(4);
}

const nodeFiles = (pkgJson.n8n && pkgJson.n8n.nodes) || [];
if (nodeFiles.length === 0) {
  console.error(`Package ${pkg} declares no n8n.nodes[] entries`);
  process.exit(5);
}

const scope = pkg.startsWith('@') ? pkg.split('/')[0] : null;
const pkgShort = pkg.startsWith('@') ? pkg.split('/')[1] : pkg;
const outDir = scope ? path.join(outBase, scope) : outBase;
fs.mkdirSync(outDir, { recursive: true });

let count = 0;
for (const relPath of nodeFiles) {
  let mod;
  try {
    mod = require(path.resolve(pkgRoot, relPath));
  } catch (e) {
    console.error(`SKIP ${relPath}: ${e.message}`);
    continue;
  }

  for (const [, cls] of Object.entries(mod)) {
    if (typeof cls !== 'function') continue;

    let inst;
    try {
      inst = new cls();
    } catch (e) {
      continue;
    }

    const desc = inst.description;
    if (!desc || !desc.name || !desc.properties) continue;

    // Full n8n type key: scoped packages prefix the package name, unscoped use desc.name only.
    const nodeType = scope ? `${pkg}.${desc.name}` : desc.name;
    const filename = `${pkgShort}.${desc.name}.json`;

    const schema = {
      type: nodeType,
      packageName: pkg,
      packageVersion: pkgJson.version,
      displayName: desc.displayName,
      description: desc.description,
      version: desc.version,
      defaults: desc.defaults,
      credentials: desc.credentials || [],
      properties: desc.properties || []
    };

    fs.writeFileSync(path.join(outDir, filename), JSON.stringify(schema, null, 2));
    console.log(`wrote ${nodeType} (${desc.properties.length} props)`);
    count++;
  }
}

// Best-effort cleanup of temp install.
try { fs.rmSync(runnerDir, { recursive: true, force: true }); } catch (e) {}

if (count === 0) {
  console.error(`No node classes extracted from ${pkg}`);
  process.exit(6);
}
