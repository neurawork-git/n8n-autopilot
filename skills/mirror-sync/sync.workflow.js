export const meta = {
  name: 'mirror-sync',
  description: 'Pull every remote-only n8n workflow into the local repo so it mirrors the instance. Deterministic: discover remote-only -> fan-out pull -> verify. Establishes/refreshes the local-first invariant the build-workflow-v2 edit flow relies on.',
  whenToUse: 'After init, or when the SessionStart drift probe reports remote workflows missing locally.',
  phases: [
    { title: 'Discover', detail: 'n8n-mirror: list --json, find remote-only workflows', model: 'sonnet' },
    { title: 'Pull', detail: 'n8n-mirror: fan-out pull <id> for each missing workflow', model: 'sonnet' },
    { title: 'Verify', detail: 're-list, confirm no remote-only remain', model: 'sonnet' },
  ],
}

const DISCOVER_SCHEMA = {
  type: 'object', required: ['remoteOnly', 'totalRemote', 'alreadyLocal'], additionalProperties: false,
  properties: {
    remoteOnly: { type: 'array', items: { type: 'object', required: ['id'], additionalProperties: false, properties: { id: { type: 'string' }, name: { type: 'string' } } } },
    totalRemote: { type: 'number' },
    alreadyLocal: { type: 'number' },
  },
}
const PULL_SCHEMA = {
  type: 'object', required: ['id', 'pulled'], additionalProperties: false,
  properties: { id: { type: 'string' }, pulled: { type: 'boolean' }, filePath: { type: ['string', 'null'] }, error: { type: ['string', 'null'] } },
}
const VERIFY_SCHEMA = {
  type: 'object', required: ['remoteOnlyRemaining'], additionalProperties: false,
  properties: { remoteOnlyRemaining: { type: 'number' }, names: { type: 'array', items: { type: 'string' } } },
}

// Env targeting:
//  - Normal: AMBIENT. Agents inherit N8NAC_ENVIRONMENT (session default from
//    repo .claude/settings.json). No flag needed; the enforce-env hook blocks any
//    bare instance call that resolves to no env, so ambient must actually be set.
//  - Override (args.env): this run targets a NON-default env -> instruct agents to
//    pass `--env <X>`. The enforce-env hook is the safety net: it hard-blocks bare
//    calls, so a dropped flag fails closed and the agent retries with it.
// args arrives as a JSON STRING from the Workflow runtime, not a parsed object — parse defensively.
const A = (typeof args === 'string') ? (() => { try { return JSON.parse(args) } catch (e) { return {} } })() : (args || {})

// ENV is NOT chosen per-call. One env per session: the agent inherits N8NAC_ENVIRONMENT
// (proven: workflow subagents inherit the session env var). Prompt-injected `--env` flags
// are agent-compliance-dependent and unreliable — forbidden. To target a different env,
// run from a session with a different N8NAC_ENVIRONMENT.
const ENV = `Run every \`npx n8nac\` command BARE (e.g. \`npx n8nac list --json\`). The target environment is ALREADY set via the inherited N8NAC_ENVIRONMENT session variable — bare commands hit the correct instance+project. Do NOT add a \`--env\` flag. Do NOT run \`npx n8nac env list\`. Do NOT probe \`default\`/other environments. Just run the bare command and trust the inherited env. `

// ===== PHASE 1 — DISCOVER =====
phase('Discover')
const disc = await agent(`${ENV}Discover remote-only workflows (workflows on the instance with no local file).`, { agentType: 'n8n-autopilot:n8n-mirror', schema: DISCOVER_SCHEMA, phase: 'Discover' })
log(`Remote total=${disc.totalRemote} | already local=${disc.alreadyLocal} | remote-only=${disc.remoteOnly.length}`)

if (disc.remoteOnly.length === 0) {
  return { status: 'success', pulled: 0, mirrorComplete: true, note: 'Local repo already mirrors the instance.' }
}

// ===== PHASE 2 — PULL (fan-out) =====
phase('Pull')
// Optional smoke-test cap. limit<=0 (default) = pull everything (no silent cap).
const limit = A.limit || 0
const targets = limit > 0 ? disc.remoteOnly.slice(0, limit) : disc.remoteOnly
if (limit > 0 && disc.remoteOnly.length > limit) log(`LIMIT active: pulling ${targets.length} of ${disc.remoteOnly.length} (smoke test)`)
log(`Pulling ${targets.length} workflow(s): ${targets.map((w) => w.name || w.id).join(', ')}`)
const pullOne = (w) => agent(`${ENV}Pull workflow id ${w.id}${w.name ? ` ("${w.name}")` : ''} into the local sync folder.`, { agentType: 'n8n-autopilot:n8n-mirror', schema: PULL_SCHEMA, phase: 'Pull' })

// Fan-out, aligned with targets (null = agent finished without emitting StructuredOutput).
let raw = await parallel(targets.map((w) => () => pullOne(w)))
// Retry the no-result ones ONCE — `pull` is idempotent, and the miss is usually a
// dropped final tool-call, not a real pull failure.
const missing = targets.filter((_, i) => !raw[i])
if (missing.length) {
  log(`${missing.length} pull(s) returned no structured result — retrying once (pull is idempotent)`)
  const retry = await parallel(missing.map((w) => () => pullOne(w)))
  let ri = 0
  raw = raw.map((r) => r || retry[ri++] || null)
}
const results = raw.filter(Boolean)

const ok = results.filter((r) => r.pulled)
const failed = results.filter((r) => !r.pulled)
if (failed.length) log(`WARNING ${failed.length} pull(s) failed: ${failed.map((f) => `${f.id} (${f.error || 'unknown'})`).join('; ')}`)

// ===== PHASE 3 — VERIFY =====
phase('Verify')
const ver = await agent(`${ENV}Re-run Discover: how many remote-only workflows remain after the pulls?`, { agentType: 'n8n-autopilot:n8n-mirror', schema: VERIFY_SCHEMA, phase: 'Verify' })

return {
  status: failed.length === 0 && ver.remoteOnlyRemaining === 0 ? 'success' : 'partial',
  pulled: ok.length,
  failed: failed.map((f) => ({ id: f.id, error: f.error })),
  remoteOnlyRemaining: ver.remoteOnlyRemaining,
  mirrorComplete: ver.remoteOnlyRemaining === 0,
  files: ok.map((r) => r.filePath).filter(Boolean),
}
