#!/usr/bin/env node
// node-schemas.mjs — dump the version-gated schema of MANY node types in ONE process.
//   npx --yes -p n8nac node scripts/node-schemas.mjs <type> [<type> …]   → JSON {type: info|null}
//
// Why: `n8nac skills node-info --json` is the only surface that returns
// schema.properties[].displayOptions['@version'] (skills batch renders docs instead), and one npx
// start costs ~7 s on Windows. n8nac's own @n8n-as-code/skills package exposes NodeSchemaProvider,
// so param-version-check.py asks for all uncached types here in a single start. Exact type match
// only — a fuzzy resolveNode() hit would judge the wrong node's versions.
import path from 'node:path'
import { pathToFileURL } from 'node:url'

const types = process.argv.slice(2)
if (!types.length) { console.error('usage: node-schemas.mjs <type> [<type> …]'); process.exit(2) }

const bin = process.env.PATH.split(path.delimiter).find((p) => p.includes('_npx') && p.endsWith('.bin'))
if (!bin) { console.error('run via: npx --yes -p n8nac node scripts/node-schemas.mjs …'); process.exit(2) }
const { NodeSchemaProvider, resolveCustomNodesConfig } = await import(pathToFileURL(path.join(bin, '..', '@n8n-as-code', 'skills', 'dist', 'index.js')).href)

// Same custom-node resolution as the CLI (n8nac-custom-nodes.json in cwd / assets dir), best effort.
let customNodesPath
try { customNodesPath = resolveCustomNodesConfig?.(process.cwd())?.customNodesPath } catch { /* none */ }
const provider = new NodeSchemaProvider(undefined, customNodesPath)

const out = {}
for (const t of types) {
  const s = provider.getNodeSchema(t)
  out[t] = s && s.schema && Array.isArray(s.schema.properties) ? s : null
}
process.stdout.write(JSON.stringify(out))
