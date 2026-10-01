// native-mcp.mjs — shared by scripts/n8n-native-proxy.mjs (plugin MCP server) and
// scripts/instance-node-check.mjs (push-lint gate).
//
// Resolves the SESSION env (N8NAC_ENVIRONMENT) through n8nac's own public API, so endpoint and token
// come from the store `npx n8nac native-mcp configure` writes. Nothing here stores or prints a token.
import { execSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'

// n8nac's package dir. Under `npx -p n8nac node …` its .bin is already on PATH; under plain `node`
// (the MCP server) ask npx once — one path, no guessing across caches.
function n8nacLibUrl() {
  let bin = process.env.PATH.split(path.delimiter).find((p) => p.includes('_npx') && p.endsWith('.bin'))
  if (!bin) {
    const out = execSync('npx --yes -p n8nac node -e "console.log(process.env.PATH)"', { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] })
    bin = out.trim().split(path.delimiter).find((p) => p.includes('_npx') && p.endsWith('.bin'))
  }
  if (!bin) throw new Error('cannot locate the n8nac package via npx')
  return `file:///${path.join(bin, '..', 'n8nac', 'dist', 'lib.js').replace(/\\/g, '/')}`
}

// Walk up to the directory holding n8nac-config.json, like the n8nac CLI does. (`native-mcp status`
// skips this walk-up and wrongly reports "disabled" from a repo dir — do not copy that.)
function configRoot(start) {
  for (let d = path.resolve(start); ; d = path.dirname(d)) {
    if (fs.existsSync(path.join(d, 'n8nac-config.json'))) return d
    if (path.dirname(d) === d) return undefined
  }
}

export async function resolveNative({ requirePin = true } = {}) {
  const envName = (process.env.N8NAC_ENVIRONMENT || '').trim()
  if (requirePin && !envName) {
    throw new Error('session env not pinned — set N8NAC_ENVIRONMENT (.claude/settings.json "env" block); refusing to guess the instance')
  }
  const { ConfigService } = await import(n8nacLibUrl())
  const start = process.env.CLAUDE_PROJECT_DIR || process.env.N8N_AS_CODE_PROJECT_DIR || process.cwd()
  const cs = new ConfigService(configRoot(start))
  const r = cs.resolveEnvironment(envName || undefined)
  const nm = r.environment.nativeMcp
  const name = r.environment.name
  if (!nm || !nm.enabled) throw new Error(`native MCP not configured for env '${name}' — docs/rules/testing.md`)
  const token = cs.getNativeMcpToken?.(r.environmentId)
  if (!token) throw new Error(`no native MCP token stored for env '${name}' — docs/rules/testing.md`)
  return { env: name, host: r.host, endpoint: nm.url || `${String(r.host).replace(/\/+$/, '')}/mcp-server/http`, token }
}

// Minimal streamable-HTTP MCP client for the instance endpoint.
export function mcpClient({ endpoint, token }) {
  let session = null
  let seq = 0
  async function post(body) {
    const headers = { 'Content-Type': 'application/json', Accept: 'application/json, text/event-stream', Authorization: `Bearer ${token}` }
    if (session) headers['mcp-session-id'] = session
    // ponytail: 429 = instance rate limit; 2 retries honouring Retry-After, then fail.
    let res
    for (let attempt = 0; ; attempt++) {
      res = await fetch(endpoint, { method: 'POST', headers, body: JSON.stringify(body) })
      if (res.status !== 429 || attempt === 2) break
      await new Promise((r) => setTimeout(r, Math.min(Number(res.headers.get('retry-after')) || 5, 30) * 1000))
    }
    if (res.headers.get('mcp-session-id')) session = res.headers.get('mcp-session-id')
    if (res.status === 401 || res.status === 403) throw new Error(`instance MCP rejected the token (HTTP ${res.status})`)
    if (!('id' in body)) return null
    const raw = await res.text()
    if (!res.ok) throw new Error(`instance MCP HTTP ${res.status}: ${raw.slice(0, 200)}`)
    const line = raw.trim().startsWith('{') ? raw : raw.split('\n').filter((l) => l.startsWith('data:')).map((l) => l.slice(5)).pop()
    const msg = JSON.parse(line)
    if (msg.error) throw new Error(`instance MCP error ${msg.error.code}: ${msg.error.message}`)
    return msg.result
  }
  const request = (method, params) => post({ jsonrpc: '2.0', id: ++seq, method, params })
  return {
    async connect() {
      session = null
      await request('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'n8n-autopilot', version: '1' } })
      await post({ jsonrpc: '2.0', method: 'notifications/initialized' })
    },
    request,
  }
}
