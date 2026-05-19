#!/usr/bin/env node
/**
 * rebuild-index.js — Walk schemas/nodes/ recursively and rebuild schemas/_index.json.
 * The index maps node type → { file, displayName, packageVersion }.
 *
 * Usage:
 *   node rebuild-index.js [workspace-root]
 */

const fs = require('fs');
const path = require('path');

const workspaceRoot = process.argv[2] || process.cwd();
const dir = path.join(workspaceRoot, 'schemas', 'nodes');

if (!fs.existsSync(dir)) {
  console.error(`schemas/nodes/ not found at ${dir}`);
  process.exit(1);
}

function collectFiles(d, prefix) {
  const result = [];
  for (const entry of fs.readdirSync(d, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      result.push(...collectFiles(path.join(d, entry.name), `${prefix}${entry.name}/`));
    } else if (entry.name.endsWith('.json') && entry.name !== '.gitkeep') {
      result.push(`${prefix}${entry.name}`);
    }
  }
  return result;
}

const files = collectFiles(dir, '');
const index = {};
for (const f of files) {
  let data;
  try {
    data = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
  } catch (e) {
    console.error(`SKIP ${f}: invalid JSON (${e.message})`);
    continue;
  }
  const type = data.type || f.replace('.json', '');
  index[type] = {
    file: f,
    displayName: data.displayName || type,
    packageVersion: data.packageVersion || null
  };
}

fs.writeFileSync(
  path.join(workspaceRoot, 'schemas', '_index.json'),
  JSON.stringify(index, null, 2)
);
console.log(`index rebuilt: ${Object.keys(index).length} schemas`);
