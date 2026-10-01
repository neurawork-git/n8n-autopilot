#!/usr/bin/env node
// n8n-native-proxy.mjs — the plugin's `n8n-native` MCP server (stdio). Forwards a fixed set of
// TEST + READ tools to the native MCP server of the instance the SESSION env points at
// (N8NAC_ENVIRONMENT). Endpoint + token come from n8nac's store (`npx n8nac native-mcp configure`),
// so a customer repo pinned to its env reaches its own instance, and no token lives in Claude Code's
// config. Write tools (create/update/archive/publish workflows, data-table writes) are not exposed:
// workflows change through the .workflow.ts file + `npx n8nac push`.
//
// Contract of the forwarded tools: docs/rules/testing.md.
import readline from 'node:readline'
import { resolveNative, mcpClient } from './lib/native-mcp.mjs'

const ALLOWED = new Set([
  'prepare_test_pin_data', 'test_workflow', 'execute_workflow', 'get_execution',
  'get_workflow_details', 'search_workflows', 'get_node_types', 'search_nodes',
])

let upstream = null // { target, client, tools }
let upstreamError = null

async function ensureUpstream() {
  if (upstream) return upstream
  const target = await resolveNative()
  const client = mcpClient(target)
  await client.connect()
  const { tools } = await client.request('tools/list', {})
  upstream = {
    target,
    client,
    tools: tools.filter((t) => ALLOWED.has(t.name)).map((t) => ({
      ...t,
      description: `[instance ${target.host} · env ${target.env}] ${t.description || ''}`,
    })),
  }
  return upstream
}

async function callUpstream(name, args) {
  const u = await ensureUpstream()
  try {
    return await u.client.request('tools/call', { name, arguments: args || {} })
  } catch (e) {
    // One reconnect for an expired upstream session, then surface the error.
    await u.client.connect()
    return await u.client.request('tools/call', { name, arguments: args || {} })
  }
}

const send = (msg) => process.stdout.write(JSON.stringify(msg) + '\n')
const reply = (id, result) => send({ jsonrpc: '2.0', id, result })
const fail = (id, code, message) => send({ jsonrpc: '2.0', id, error: { code, message } })
const toolError = (id, text) => reply(id, { content: [{ type: 'text', text }], isError: true })

async function handle(msg) {
  const { id, method, params } = msg
  if (id === undefined) return // notification
  switch (method) {
    case 'initialize':
      return reply(id, {
        protocolVersion: params?.protocolVersion || '2025-06-18',
        capabilities: { tools: {} },
        serverInfo: { name: 'n8n-native (n8n-autopilot)', version: '1.0.0' },
        instructions: 'Test/read access to the n8n instance of the session env. Default test: prepare_test_pin_data -> test_workflow (no side effects). execute_workflow calls real services. Workflows must have settings.availableInMCP: true.',
      })
    case 'ping':
      return reply(id, {})
    case 'tools/list':
      try {
        return reply(id, { tools: (await ensureUpstream()).tools })
      } catch (e) {
        upstreamError = String(e.message || e)
        // Still list the tools, so callers get the real reason on the call instead of "no such tool".
        return reply(id, { tools: [...ALLOWED].map((name) => ({ name, description: `UNAVAILABLE: ${upstreamError}`, inputSchema: { type: 'object', additionalProperties: true } })) })
      }
    case 'tools/call': {
      const name = params?.name
      if (!ALLOWED.has(name)) return toolError(id, `'${name}' is not exposed by n8n-autopilot: n8n-native is test/read-only. Change workflows via the .workflow.ts file + npx n8nac push.`)
      try {
        return reply(id, await callUpstream(name, params.arguments))
      } catch (e) {
        upstream = null
        return toolError(id, `n8n-native unavailable: ${e.message || e}`)
      }
    }
    default:
      return fail(id, -32601, `method not found: ${method}`)
  }
}

readline.createInterface({ input: process.stdin }).on('line', (line) => {
  if (!line.trim()) return
  let msg
  try { msg = JSON.parse(line) } catch { return fail(null, -32700, 'parse error') }
  handle(msg).catch((e) => fail(msg.id ?? null, -32603, String(e.message || e)))
})
