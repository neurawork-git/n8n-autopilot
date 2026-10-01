#!/usr/bin/env node
// instance-node-check.mjs — ask the RUNNING n8n instance (session env) whether every node type +
// typeVersion of a compiled workflow exists there. Called by push-lint-gate.sh:
//   node scripts/instance-node-check.mjs <compiled.json>
//
// Why not n8nac itself: its push preflight only WARNS when the instance does not describe a
// type@version and then validates against the bundled catalogue (stamped for another n8n version);
// level-2 validation needs `validate_node_config`, which the instance may not expose; and its MCP
// broker sends `version` as a number, which the instance rejects (-32602). The instance's own
// `get_node_types` answers precisely: "Version 'X' not found for node 'T'" / "Node type 'T' not found".
//
// Only CORE packages (n8n-nodes-base, @n8n/n8n-nodes-langchain) are enforced. The instance catalogue
// does not cover every installed community node (2026-09-22: n8n-nodes-pandadoc answered "not found"
// while it ran on the same instance that day) — community findings are `warnings`. The catalogue
// also omits HIDDEN (deprecated) core nodes — spreadsheetFile, function, itemLists answer "not found"
// although the instance still runs them. Blocking those is intended: new pushes use current nodes.
//
// Exit: 0 = no core blocker · 1 = a core node type/version is missing · 2 = check impossible
// (env not pinned, native MCP not configured, unreachable, token rejected).
import fs from 'node:fs'
import { resolveNative, mcpClient } from './lib/native-mcp.mjs'

const out = (o, code) => { console.log(JSON.stringify(o, null, 2)); process.exit(code) }
const file = process.argv[2]
if (!file) out({ ok: false, error: 'usage: instance-node-check.mjs <compiled-workflow.json>' }, 2)

let target, client
try {
  target = await resolveNative()
  client = mcpClient(target)
  await client.connect()
} catch (e) {
  out({ ok: false, error: String(e.message || e) }, 2)
}

const wf = JSON.parse(fs.readFileSync(file, 'utf8'))
const nodes = (wf.nodes || []).filter((n) => !n.disabled && n.type.toLowerCase() !== 'n8n-nodes-base.stickynote')

// One descriptor per distinct type@version. Discriminators are passed when the node has them;
// a remaining "requires … discriminator" answer is not a version problem and is ignored.
const byKey = new Map()
for (const n of nodes) {
  const k = `${n.type}@${n.typeVersion ?? 1}`
  if (!byKey.has(k)) byKey.set(k, { node: n, names: [] })
  byKey.get(k).names.push(n.name)
}
const CORE = /^(n8n-nodes-base|@n8n\/n8n-nodes-langchain)\./
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\@/]/g, '\\$&')
const blockers = []
const warnings = []
const entries = [...byKey.values()]
for (let i = 0; i < entries.length; i += 25) {
  const chunk = entries.slice(i, i + 25)
  const nodeIds = chunk.map(({ node }) => {
    const p = node.parameters || {}
    const d = { nodeId: node.type, version: String(node.typeVersion ?? 1) }
    for (const f of ['resource', 'operation', 'mode']) if (typeof p[f] === 'string' && !p[f].startsWith('=')) d[f] = p[f]
    return d
  })
  let text
  try {
    const r = await client.request('tools/call', { name: 'get_node_types', arguments: { nodeIds } })
    text = (r?.content || []).map((c) => c.text || '').join('\n')
  } catch (e) {
    out({ ok: false, error: `get_node_types failed: ${e.message || e}` }, 2)
  }
  for (const { node, names } of chunk) {
    const v = String(node.typeVersion ?? 1)
    const core = CORE.test(node.type)
    const sink = core ? blockers : warnings
    if (new RegExp(`Node type '${esc(node.type)}' not found`).test(text)) {
      sink.push({ nodes: names, type: node.type, version: v, msg: core ? 'not in the instance node catalogue — deprecated/hidden (spreadsheetFile, function, itemLists, …) or nonexistent; use the current replacement node' : 'not in the instance MCP catalogue (community node — unverifiable, may still be installed)' })
    } else if (new RegExp(`Version '${esc(v)}' not found for node '${esc(node.type)}'`).test(text)) {
      sink.push({ nodes: names, type: node.type, version: v, msg: `typeVersion ${v} does not exist on the instance` })
    }
  }
}
out({ ok: blockers.length === 0, env: target.env, endpoint: target.endpoint, checked: entries.length, blockers, warnings }, blockers.length ? 1 : 0)
