export const meta = {
  name: 'build-workflow-v2-edit',
  description: 'Deterministic JS-orchestrated EDIT of an EXISTING n8n workflow. Local-first (assumes the repo mirrors remote workflows); refreshes the target to remote base before patching, then runs the same hard gates as greenfield (validate / drift-safe push --verify / test). Roles live in agents/n8n-*.md.',
  whenToUse: 'Change a workflow that already exists on the instance, drift-safely.',
  phases: [
    { title: 'Comprehend', detail: 'n8n-comprehender resolves target, refreshes to remote base, summarizes change site', model: 'sonnet' },
    { title: 'Verify', detail: 'n8n-node-verifier param fan-out for any newly introduced node types', model: 'sonnet' },
    { title: 'Patch', detail: 'n8n-author applies the change, preserves the rest', model: 'opus' },
    { title: 'Validate', detail: 'n8n-validator hard gate (max 3 fix cycles)', model: 'sonnet' },
    { title: 'Review', detail: 'workflow-reviewer design-quality gate (max 2 fix cycles)', model: 'sonnet' },
    { title: 'Deploy', detail: 'n8n-deployer drift-safe push --verify hard gate', model: 'sonnet' },
    { title: 'Test', detail: 'n8n-tester classify -> Path A live test loop / Path B handoff', model: 'sonnet' },
  ],
}

const COMPREHEND_SCHEMA = {
  type: 'object', required: ['workflowId', 'filePath', 'triggerType', 'localPresent'], additionalProperties: false,
  properties: {
    workflowId: { type: 'string' },
    filePath: { type: 'string', description: 'absolute path of the local .workflow.ts (after refresh)' },
    triggerType: { type: 'string' },
    hasMcpTrigger: { type: 'boolean' },
    localPresent: { type: 'boolean', description: 'true if the file already existed locally (mirror invariant held)' },
    refreshed: { type: 'boolean', description: 'true if a pull/fetch was needed to reach remote base' },
    driftStatus: { type: ['string', 'null'] },
    summary: { type: 'string', description: 'current shape: trigger, nodes, links, creds' },
    changeSite: { type: 'string', description: 'which node(s)/links/params the requested change touches + risks' },
    newNodeTypes: { type: 'array', items: { type: 'string' }, description: 'node types the change will introduce (need verification)' },
  },
}
const NODE_CONTRACT_SCHEMA = {
  type: 'object', required: ['type', 'found', 'params'], additionalProperties: false,
  properties: { type: { type: 'string' }, found: { type: 'boolean' }, typeVersion: { type: ['number', 'null'] }, params: { type: 'array', items: { type: 'object', required: ['name'], additionalProperties: false, properties: { name: { type: 'string' }, required: { type: 'boolean' } } } }, credentialKeys: { type: 'array', items: { type: 'string' } }, notes: { type: 'string' } },
}
const AUTHOR_SCHEMA = { type: 'object', required: ['filePath', 'written'], additionalProperties: false, properties: { filePath: { type: 'string' }, written: { type: 'boolean' }, summary: { type: 'string' } } }
const VALIDATE_SCHEMA = { type: 'object', required: ['passed', 'errors'], additionalProperties: false, properties: { passed: { type: 'boolean' }, errors: { type: 'array', items: { type: 'string' } } } }
const REVIEW_SCHEMA = { type: 'object', required: ['blockers', 'warnings'], additionalProperties: false, properties: { blockers: { type: 'array', items: { type: 'string' } }, warnings: { type: 'array', items: { type: 'string' } } } }
const PUSH_SCHEMA = { type: 'object', required: ['pushed', 'verified'], additionalProperties: false, properties: { pushed: { type: 'boolean' }, verified: { type: 'boolean' }, workflowId: { type: ['string', 'null'] }, driftStatus: { type: ['string', 'null'] }, error: { type: ['string', 'null'] } } }
const TESTPLAN_SCHEMA = { type: 'object', required: ['triggerType', 'testable'], additionalProperties: false, properties: { triggerType: { type: 'string' }, testable: { type: 'boolean' }, suggestedPayload: { type: ['string', 'null'] }, presentUrl: { type: ['string', 'null'] } } }
const TEST_SCHEMA = { type: 'object', required: ['outcome'], additionalProperties: false, properties: { outcome: { type: 'string', enum: ['success', 'classA', 'classB', 'runtime-state', 'error'] }, executionId: { type: ['string', 'null'] }, executionStatus: { type: ['string', 'null'] }, errors: { type: 'array', items: { type: 'string' } }, outputSample: { type: 'string' } } }

// args arrives as a JSON STRING from the Workflow runtime — parse defensively.
const A = (() => { if (typeof args !== 'string') return args || {}; try { return JSON.parse(args) } catch (e) { return {} } })()
const target = A.target || A.workflowId || A.name || ''
const change = A.change || A.description || ''
const userTestData = A.testData || ''
if (!target || !change) { log('Need args.target (workflow id/name) and args.change (what to change).'); return { status: 'aborted', reason: 'missing-target-or-change' } }

// safe(): a schema'd subagent that ends WITHOUT calling StructuredOutput (or dies terminally) crashes
// the whole run with an opaque error. One retry, then a graceful fallback into the existing gate-failure
// handling. ponytail: 2 attempts max — rare failures, double-cost worst case beats an opaque abort.
async function safe(prompt, opts, fallback) {
  for (let i = 1; i <= 2; i++) {
    try { const r = await agent(prompt, opts); if (r != null) return r } catch (e) { log(`agent(${opts.phase || '?'}) attempt ${i}/2 failed: ${String((e && e.message) || e).slice(0, 140)}`) }
  }
  log(`agent(${opts.phase || '?'}) produced no output after 2 attempts -> graceful fallback`)
  return fallback
}

// ===== PHASE 1 — COMPREHEND (local-first, refresh to remote base) =====
phase('Comprehend')
const ctx = await safe(
  `An existing n8n workflow needs editing.\nTarget (id or name): "${target}"\nRequested change: """${change}"""\nFollow your procedure. The repo is expected to mirror remote workflows locally — prefer the LOCAL file. Detect drift (fetch + list --search --json); if the local file is stale or missing, pull to reach remote base and set refreshed=true (and localPresent accordingly). Summarize the current shape, name the change site + risks, and list any node types the change will INTRODUCE in newNodeTypes.`,
  { agentType: 'n8n-autopilot:n8n-comprehender', schema: COMPREHEND_SCHEMA, phase: 'Comprehend' },
  null
)
if (!ctx) return { status: 'failed', stage: 'comprehend', error: 'comprehender produced no output after retries', target }
if (!ctx.localPresent) log(`NOTE: local mirror missing for ${ctx.workflowId} — pulled fresh (mirror invariant was broken).`)
if (ctx.driftStatus && !['TRACKED', 'LOCAL_ONLY', null].includes(ctx.driftStatus)) log(`Drift before edit: ${ctx.driftStatus} -> refreshed=${ctx.refreshed}`)
const FILE = ctx.filePath
const WID = ctx.workflowId
log(`Editing ${WID} @ ${FILE} | trigger=${ctx.triggerType} | newNodes=${(ctx.newNodeTypes || []).length}`)

// ===== PHASE 2 — VERIFY new node types =====
phase('Verify')
let contractBlock = '(no new node types)'
if (ctx.newNodeTypes && ctx.newNodeTypes.length) {
  const contracts = (await parallel(ctx.newNodeTypes.map((t) => () =>
    agent(`Verify the parameter contract for node type "${t}".`, { agentType: 'n8n-autopilot:n8n-node-verifier', schema: NODE_CONTRACT_SCHEMA, phase: 'Verify' })
  ))).filter(Boolean)
  contractBlock = contracts.map((c) => `- ${c.type} (v${c.typeVersion ?? '?'}): params=[${c.params.map((p) => p.name).join(', ')}]${c.found ? '' : ' [SCHEMA MISSING]'}`).join('\n')
}

// ===== PHASE 3 — PATCH =====
phase('Patch')
const patched = await safe(
  `Apply this change to the EXISTING workflow file ${FILE}:\n"""${change}"""\nChange site (from comprehension): ${ctx.changeSite}\nPreserve everything else (id, name, unrelated nodes/links). Verified contracts for any new node types:\n${contractBlock}\nDo NOT change the @workflow id. Use Edit (not full rewrite) where possible.`,
  { agentType: 'n8n-autopilot:n8n-author', schema: AUTHOR_SCHEMA, model: 'opus', phase: 'Patch' },
  { written: false, summary: 'patch agent produced no output' }
)
if (!patched.written) return { status: 'failed', stage: 'patch', detail: patched.summary || 'no edit written', filePath: FILE }

// ===== PHASE 4 — VALIDATE GATE =====
phase('Validate')
let vRes = null, vCycle = 0
while (true) {
  vRes = await safe(`Validate the file: ${FILE}`, { agentType: 'n8n-autopilot:n8n-validator', schema: VALIDATE_SCHEMA, phase: 'Validate' }, { passed: false, errors: ['validator produced no output'] })
  if (vRes.passed) { log(`Validate passed (cycle ${vCycle})`); break }
  vCycle++
  if (vCycle > 3) return { status: 'failed', stage: 'validate', cycles: vCycle - 1, errors: vRes.errors, filePath: FILE }
  log(`Validate failed (cycle ${vCycle}) -> fixing`)
  await safe(`Fix these validation errors in ${FILE} (preserve the intended change):\n${vRes.errors.map((e) => '- ' + e).join('\n')}`, { agentType: 'n8n-autopilot:n8n-author', schema: AUTHOR_SCHEMA, model: 'opus', phase: 'Validate' }, {})
}

// ===== PHASE 4b — REVIEW GATE (design quality the validator cannot catch) =====
phase('Review')
let rev = null, rCycle = 0
while (true) {
  rev = await safe(`Review ${FILE} for DESIGN-QUALITY blockers the n8n validator does NOT catch: raw HTTP in Code nodes ($helpers.httpRequest*), continueOnFail/onError:continue that masks real errors, AI sub-nodes wired via .out().to() instead of .uses() in @links(), missing error handling on external calls. Return blockers (the "Issues (must fix)" tier — hard repo-rule violations) separately from warnings (advisory only). Do NOT re-flag schema/wiring errors the validator already gates, and do NOT flag pre-existing issues outside the change site.`, { agentType: 'n8n-autopilot:workflow-reviewer', schema: REVIEW_SCHEMA, phase: 'Review' }, { blockers: [], warnings: [] })
  if (!rev.blockers.length) { log(`Review passed (cycle ${rCycle})${rev.warnings.length ? `, ${rev.warnings.length} warning(s)` : ''}`); break }
  rCycle++
  if (rCycle > 2) return { status: 'failed', stage: 'review', cycles: rCycle - 1, blockers: rev.blockers, warnings: rev.warnings, filePath: FILE }
  log(`Review found ${rev.blockers.length} blocker(s) (cycle ${rCycle}) -> fixing`)
  // ponytail: no re-validate after a design-fix; the Deploy push --verify is the schema backstop.
  await safe(`Fix these DESIGN-QUALITY blockers in ${FILE} (preserve the intended change):\n${rev.blockers.map((e) => '- ' + e).join('\n')}`, { agentType: 'n8n-autopilot:n8n-author', schema: AUTHOR_SCHEMA, model: 'opus', phase: 'Review' }, {})
}

// ===== PHASE 5 — DEPLOY GATE (drift-safe) =====
phase('Deploy')
const pushRes = await safe(`Deploy + verify the file: ${FILE} (drift-check first; do NOT bypass the push-gate).`, { agentType: 'n8n-autopilot:n8n-deployer', schema: PUSH_SCHEMA, phase: 'Deploy' }, { pushed: false, verified: false, workflowId: null, driftStatus: null, error: 'deployer produced no output' })
if (!pushRes.pushed || !pushRes.verified) {
  // Drift here means remote changed DURING this run (we refreshed at comprehend). Surface, do not clobber.
  return { status: 'failed', stage: 'deploy', driftStatus: pushRes.driftStatus, error: pushRes.error || 'push/verify failed', filePath: FILE, hint: pushRes.driftStatus ? 'Remote changed during the edit run. Re-run the edit flow to pick up the new base.' : undefined }
}
log(`Pushed + verified. workflowId=${WID}`)

// ===== PHASE 6 — TEST =====
phase('Test')
const tp = await agent(`Classify how workflow ${WID} can be tested (test-plan + present URL).`, { agentType: 'n8n-autopilot:n8n-tester', schema: TESTPLAN_SCHEMA, phase: 'Test' })
const HTTP = ['webhook', 'chat', 'form']
let test = null
if (HTTP.includes(tp.triggerType) && tp.testable) {
  const payload = userTestData || tp.suggestedPayload || ''
  let tCycle = 0
  while (true) {
    test = await agent(`Live-test workflow ${WID} (trigger=${tp.triggerType})${payload ? ` with payload ${payload}` : ''}, then inspect the execution.`, { agentType: 'n8n-autopilot:n8n-tester', schema: TEST_SCHEMA, phase: 'Test' })
    if (test.outcome !== 'classB') break
    tCycle++
    if (tCycle > 3) { log('Class B persists after 3 cycles'); break }
    log(`Class B (cycle ${tCycle}) -> fix -> revalidate -> repush`)
    await agent(`Fix these Class-B wiring errors in ${FILE}:\n${test.errors.map((e) => '- ' + e).join('\n')}`, { agentType: 'n8n-autopilot:n8n-author', schema: AUTHOR_SCHEMA, model: 'opus', phase: 'Test' })
    const rv = await agent(`Validate the file: ${FILE}`, { agentType: 'n8n-autopilot:n8n-validator', schema: VALIDATE_SCHEMA, phase: 'Test' })
    if (!rv.passed) { test = { outcome: 'classB', executionId: null, executionStatus: null, errors: rv.errors, outputSample: '' }; break }
    const rp = await agent(`Deploy + verify the file: ${FILE}.`, { agentType: 'n8n-autopilot:n8n-deployer', schema: PUSH_SCHEMA, phase: 'Test' })
    if (!rp.pushed || !rp.verified) { test = { outcome: 'error', executionId: null, executionStatus: null, errors: [rp.error || 'repush failed'], outputSample: '' }; break }
  }
} else {
  test = { outcome: 'manual-required', triggerType: tp.triggerType, presentUrl: tp.presentUrl, note: ctx.hasMcpTrigger ? 'mcpTrigger: Publish in UI, then /n8n-autopilot:test-manual.' : 'Non-HTTP trigger: Execute Workflow in UI, then /n8n-autopilot:test-manual.' }
  log(`Non-HTTP trigger (${tp.triggerType}) — handing back for manual test`)
}

return { status: 'success', mode: 'edit', workflowId: WID, filePath: FILE, url: tp.presentUrl, triggerType: tp.triggerType, hasMcpTrigger: ctx.hasMcpTrigger, localMirrorHeld: ctx.localPresent, refreshed: ctx.refreshed, validateCycles: vCycle, reviewWarnings: rev ? rev.warnings : [], test }
