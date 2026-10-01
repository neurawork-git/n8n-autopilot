#!/usr/bin/env node
// check-native-mcp.mjs — is the SESSION env ready for the native-MCP test path + the push-lint gate?
//   node scripts/check-native-mcp.mjs [--live] [--quiet]
// Offline by default (config + stored token only, for SessionStart). --live also connects and
// lists the instance tools (check-mcps). INFO only, never AUTOPILOT_ACTION_REQUIRED: the fix needs a
// token from the n8n UI, which no automated action can produce.
// Silent when N8NAC_ENVIRONMENT is unset — the env-gate already reports that.
import { resolveNative, mcpClient } from './lib/native-mcp.mjs'

const live = process.argv.includes('--live')
const quiet = process.argv.includes('--quiet')
const env = (process.env.N8NAC_ENVIRONMENT || '').trim()
if (!env) process.exit(0)

const REMEDY = `configure it once for env '${env}' in YOUR terminal (token: n8n UI → Settings → MCP; pipe it in):
    $t = Read-Host "n8n MCP Token" -MaskInput; $t | npx n8nac native-mcp configure ${env} --token-stdin --level 2
  Until then the push-lint gate blocks every push and n8n-native tests fail. Details: docs/rules/testing.md`

try {
  const t = await resolveNative()
  if (live) {
    const c = mcpClient(t)
    await c.connect()
    const { tools } = await c.request('tools/list', {})
    const names = tools.map((x) => x.name)
    const need = ['prepare_test_pin_data', 'test_workflow', 'execute_workflow', 'get_execution', 'get_node_types']
    const missing = need.filter((n) => !names.includes(n))
    if (missing.length) {
      console.log(`INFO: native MCP of ${t.host} (env ${t.env}) lacks ${missing.join(', ')} — n8n too old for the test path (needs n8n >= 2.20).`)
      process.exit(1)
    }
    console.log(`✅ native MCP ready — env ${t.env} → ${t.host} (${names.length} instance tools; test + node checks available)`)
  } else if (!quiet) {
    console.log(`✅ native MCP configured — env ${t.env} → ${t.host}`)
  }
} catch (e) {
  // WARN, not INFO: with the env pinned, this blocks EVERY push (push-lint gate stage 1) and every
  // n8n-native test — a nightly build run stalls on it. Still no AUTOPILOT_ACTION_REQUIRED: the
  // remedy needs a token from the n8n UI that no automated action can produce.
  console.log(`WARN: native MCP not ready for env '${env}' — every push is blocked until fixed: ${e.message || e}\n  → ${REMEDY}`)
  process.exit(live ? 1 : 0)
}
