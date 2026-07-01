export const meta = {
  name: 'build-workflow-v2-greenfield',
  description: 'Deterministic JS-orchestrated NEW n8n workflow build. Gates (validate / push --verify) and fix-loop limits are JS control flow, not model discretion. Roles live in agents/n8n-*.md; this script is pure orchestration + schemas + tasks.',
  whenToUse: 'Ship a brand-new n8n workflow with the gate sequence enforced by code.',
  phases: [
    { title: 'Research', detail: 'n8n-researcher plan + n8n-node-verifier param fan-out', model: 'sonnet' },
    { title: 'Author', detail: 'n8n-author writes .workflow.ts from verified contracts', model: 'opus' },
    { title: 'Validate', detail: 'n8n-validator hard gate (max 3 fix cycles)', model: 'sonnet' },
    { title: 'Review', detail: 'workflow-reviewer design-quality gate (max 2 fix cycles)', model: 'sonnet' },
    { title: 'Deploy', detail: 'n8n-deployer push --verify hard gate', model: 'sonnet' },
    { title: 'Test', detail: 'n8n-tester classify -> Path A live test loop / Path B handoff', model: 'sonnet' },
  ],
}

// --- Schemas: orchestration contracts (the DECISION is JS; agents fill these) --
const PLAN_SCHEMA = {
  type: 'object', required: ['workflowName', 'triggerType', 'nodes', 'hasMcpTrigger', 'syncFolder'], additionalProperties: false,
  properties: {
    workflowName: { type: 'string' },
    triggerType: { type: 'string', enum: ['webhook', 'chat', 'form', 'schedule', 'manual', 'errorTrigger', 'telegram', 'unknown'] },
    nodes: { type: 'array', items: { type: 'object', required: ['type', 'purpose'], additionalProperties: false, properties: { type: { type: 'string' }, purpose: { type: 'string' } } } },
    hasMcpTrigger: { type: 'boolean' },
    templateId: { type: ['string', 'null'] },
    suggestedTestData: { type: 'string' },
    syncFolder: { type: 'string' },
  },
}
const NODE_CONTRACT_SCHEMA = {
  type: 'object', required: ['type', 'found', 'params'], additionalProperties: false,
  properties: {
    type: { type: 'string' }, found: { type: 'boolean' }, typeVersion: { type: ['number', 'null'] },
    params: { type: 'array', items: { type: 'object', required: ['name'], additionalProperties: false, properties: { name: { type: 'string' }, required: { type: 'boolean' } } } },
    credentialKeys: { type: 'array', items: { type: 'string' } }, notes: { type: 'string' },
  },
}
const AUTHOR_SCHEMA = { type: 'object', required: ['filePath', 'written'], additionalProperties: false, properties: { filePath: { type: 'string' }, written: { type: 'boolean' }, summary: { type: 'string' } } }
const VALIDATE_SCHEMA = { type: 'object', required: ['passed', 'errors'], additionalProperties: false, properties: { passed: { type: 'boolean' }, errors: { type: 'array', items: { type: 'string' } } } }
const REVIEW_SCHEMA = { type: 'object', required: ['blockers', 'warnings'], additionalProperties: false, properties: { blockers: { type: 'array', items: { type: 'string' } }, warnings: { type: 'array', items: { type: 'string' } } } }
const PUSH_SCHEMA = { type: 'object', required: ['pushed', 'verified'], additionalProperties: false, properties: { pushed: { type: 'boolean' }, verified: { type: 'boolean' }, workflowId: { type: ['string', 'null'] }, driftStatus: { type: ['string', 'null'] }, error: { type: ['string', 'null'] } } }
const TESTPLAN_SCHEMA = { type: 'object', required: ['triggerType', 'testable'], additionalProperties: false, properties: { triggerType: { type: 'string' }, testable: { type: 'boolean' }, suggestedPayload: { type: ['string', 'null'] }, presentUrl: { type: ['string', 'null'] } } }
const CRED_SCHEMA = { type: 'object', required: ['allPresent'], additionalProperties: false, properties: { allPresent: { type: 'boolean' }, missing: { type: 'array', items: { type: 'string' } } } }
const TEST_SCHEMA = { type: 'object', required: ['outcome'], additionalProperties: false, properties: { outcome: { type: 'string', enum: ['success', 'classA', 'classB', 'runtime-state', 'error'] }, executionId: { type: ['string', 'null'] }, executionStatus: { type: ['string', 'null'] }, errors: { type: 'array', items: { type: 'string' } }, outputSample: { type: 'string' } } }

// Plugin agents resolve namespaced as `<plugin>:<agent>` (proven: prp-core:* spawns in Workflow).
const ACTIVATE_SCHEMA = { type: 'object', required: ['activated'], additionalProperties: false, properties: { activated: { type: 'boolean' }, error: { type: ['string', 'null'] } } }

// args arrives as a JSON STRING from the Workflow runtime — parse defensively (bare string = description).
const A = (() => { if (typeof args !== 'string') return args || {}; try { return JSON.parse(args) } catch (e) { return { description: args } } })()
const desc = A.description || ''
const userTestData = A.testData || ''

// safe(): a schema'd subagent that ends WITHOUT calling StructuredOutput (or dies terminally) makes
// agent() throw/return null and crashes the whole run with an opaque error (observed: a heavy agent
// burned ~786k tokens, then the workflow aborted). One retry, then a graceful fallback that routes into
// the EXISTING gate-failure handling instead of crashing. ponytail: 2 attempts max — these failures are
// rare; the double-cost worst case still beats an opaque mid-run abort.
async function safe(prompt, opts, fallback) {
  for (let i = 1; i <= 2; i++) {
    try { const r = await agent(prompt, opts); if (r != null) return r } catch (e) { log(`agent(${opts.phase || '?'}) attempt ${i}/2 failed: ${String((e && e.message) || e).slice(0, 140)}`) }
  }
  log(`agent(${opts.phase || '?'}) produced no output after 2 attempts -> graceful fallback`)
  return fallback
}
if (!desc) { log('No description (args.description empty).'); return { status: 'aborted', reason: 'no-description' } }

// ===== PHASE 1 — RESEARCH =====
phase('Research')
const plan = await safe(
  `Plan an n8n workflow for this request:\n"""${desc}"""\nFollow your procedure: resolve sync folder, mandatory community-template lookup, node discovery (exact types), trigger classification, suggested test data.`,
  { agentType: 'n8n-autopilot:n8n-researcher', schema: PLAN_SCHEMA, phase: 'Research' },
  null
)
if (!plan) return { status: 'failed', stage: 'research', error: 'planner produced no output after retries' }
log(`Plan: "${plan.workflowName}" | trigger=${plan.triggerType} | nodes=${plan.nodes.length} | template=${plan.templateId || 'none'} | mcp=${plan.hasMcpTrigger}`)

const contracts = (await parallel(
  plan.nodes.map((n) => () =>
    agent(`Verify the parameter contract for node type "${n.type}" (purpose: ${n.purpose}).`,
      { agentType: 'n8n-autopilot:n8n-node-verifier', schema: NODE_CONTRACT_SCHEMA, phase: 'Research' })
  )
)).filter(Boolean)
const missingSchemas = contracts.filter((c) => !c.found).map((c) => c.type)
if (missingSchemas.length) log(`WARNING missing schemas: ${missingSchemas.join(', ')} — consider /n8n-autopilot:pull-schemas`)

// ===== PHASE 2 — AUTHOR =====
phase('Author')
const contractBlock = contracts.map((c) => `- ${c.type} (v${c.typeVersion ?? '?'}): params=[${c.params.map((p) => p.name).join(', ')}]${c.credentialKeys?.length ? ` creds=[${c.credentialKeys.join(', ')}]` : ''}${c.found ? '' : ' [SCHEMA MISSING]'}`).join('\n')
const authored = await safe(
  `Write a NEW n8n Decorator-TS workflow.\nRequest: """${desc}"""\nWorkflow name: ${plan.workflowName}\nTrigger: ${plan.triggerType}\nSync folder (write the file here): ${plan.syncFolder}\n${plan.templateId ? `Seed from community template id ${plan.templateId} (npx n8nac skills examples download ${plan.templateId} into the sync folder), then adapt.` : 'Author from scratch.'}\nhasMcpTrigger: ${plan.hasMcpTrigger}\nVerified node contracts (use ONLY these param names):\n${contractBlock}`,
  { agentType: 'n8n-autopilot:n8n-author', schema: AUTHOR_SCHEMA, model: 'opus', phase: 'Author' },
  { written: false, summary: 'author agent produced no output' }
)
if (!authored.written) return { status: 'failed', stage: 'author', detail: authored.summary || 'no file written' }
const FILE = authored.filePath
log(`Authored ${FILE}`)

// ===== PHASE 3 — VALIDATE GATE =====
phase('Validate')
let vRes = null, vCycle = 0
while (true) {
  vRes = await safe(`Validate the file: ${FILE}`, { agentType: 'n8n-autopilot:n8n-validator', schema: VALIDATE_SCHEMA, phase: 'Validate' }, { passed: false, errors: ['validator produced no output'] })
  if (vRes.passed) { log(`Validate passed (cycle ${vCycle})`); break }
  vCycle++
  if (vCycle > 3) return { status: 'failed', stage: 'validate', cycles: vCycle - 1, errors: vRes.errors, filePath: FILE }
  log(`Validate failed (cycle ${vCycle}): ${vRes.errors.length} issue(s) -> fixing`)
  await safe(`Fix these validation errors in ${FILE}:\n${vRes.errors.map((e) => '- ' + e).join('\n')}`, { agentType: 'n8n-autopilot:n8n-author', schema: AUTHOR_SCHEMA, model: 'opus', phase: 'Validate' }, {})
}

// ===== PHASE 3b — REVIEW GATE (design quality the validator cannot catch) =====
phase('Review')
let rev = null, rCycle = 0
while (true) {
  rev = await safe(`Review ${FILE} for DESIGN-QUALITY blockers the n8n validator does NOT catch: raw HTTP in Code nodes ($helpers.httpRequest*), continueOnFail/onError:continue that masks real errors, AI sub-nodes wired via .out().to() instead of .uses() in @links(), missing error handling on external calls. Return blockers (the "Issues (must fix)" tier — hard repo-rule violations) separately from warnings (advisory only). Do NOT re-flag schema/wiring errors the validator already gates.`, { agentType: 'n8n-autopilot:workflow-reviewer', schema: REVIEW_SCHEMA, phase: 'Review' }, { blockers: [], warnings: [] })
  if (!rev.blockers.length) { log(`Review passed (cycle ${rCycle})${rev.warnings.length ? `, ${rev.warnings.length} warning(s)` : ''}`); break }
  rCycle++
  if (rCycle > 2) return { status: 'failed', stage: 'review', cycles: rCycle - 1, blockers: rev.blockers, warnings: rev.warnings, filePath: FILE }
  log(`Review found ${rev.blockers.length} blocker(s) (cycle ${rCycle}) -> fixing`)
  // ponytail: no re-validate after a design-fix; the Deploy push --verify is the schema backstop.
  await safe(`Fix these DESIGN-QUALITY blockers in ${FILE} (preserve intended behavior):\n${rev.blockers.map((e) => '- ' + e).join('\n')}`, { agentType: 'n8n-autopilot:n8n-author', schema: AUTHOR_SCHEMA, model: 'opus', phase: 'Review' }, {})
}

// ===== PHASE 4 — DEPLOY GATE =====
phase('Deploy')
const pushRes = await safe(`Deploy + verify the file: ${FILE} (drift-check first).`, { agentType: 'n8n-autopilot:n8n-deployer', schema: PUSH_SCHEMA, phase: 'Deploy' }, { pushed: false, verified: false, workflowId: null, driftStatus: null, error: 'deployer produced no output' })
if (!pushRes.pushed || !pushRes.verified || !pushRes.workflowId)
  return { status: 'failed', stage: 'deploy', driftStatus: pushRes.driftStatus, error: pushRes.error || 'push/verify failed or no workflowId', filePath: FILE }
const WID = pushRes.workflowId
log(`Pushed + verified. workflowId=${WID}`)

// ===== PHASE 5 — TEST =====
phase('Test')
const tp = await agent(`Classify how workflow ${WID} can be tested (test-plan + present URL).`, { agentType: 'n8n-autopilot:n8n-tester', schema: TESTPLAN_SCHEMA, phase: 'Test' })
const cred = await agent(`Check credential readiness for workflow ${WID} (credential-required).`, { agentType: 'n8n-autopilot:n8n-tester', schema: CRED_SCHEMA, phase: 'Test' })
if (!cred.allPresent) log(`Credentials missing: ${cred.missing.join(', ')} (Class A)`)

const HTTP = ['webhook', 'chat', 'form']
let test = null, activated = false
if (HTTP.includes(tp.triggerType) && tp.testable) {
  // Headless `n8nac test` CANNOT arm the editor-only TEST webhook. The autopilot way to
  // fire an HTTP trigger with ZERO human steps: ACTIVATE the workflow -> hit the PRODUCTION
  // URL. Activation failure is ESCALATED, never swallowed. No "arm it in the editor" answers.
  const act = await agent(`Activate workflow ${WID} so its production webhook registers: run \`npx n8nac workflow activate ${WID}\`. activated=true ONLY if it is now active.`, { agentType: 'n8n-autopilot:n8n-tester', schema: ACTIVATE_SCHEMA, phase: 'Test' })
  activated = !!act.activated
  if (!activated) return { status: 'failed', stage: 'activate', mode: 'greenfield', workflowName: plan.workflowName, workflowId: WID, filePath: FILE, url: tp.presentUrl, error: act.error || 'activation failed — webhook unregistered, cannot receive calls', validateCycles: vCycle }
  const payload = userTestData || tp.suggestedPayload || plan.suggestedTestData || ''
  let tCycle = 0
  while (true) {
    test = await agent(`Live-test workflow ${WID} via its PRODUCTION URL (the workflow is ACTIVE): \`npx n8nac test ${WID} --prod${payload ? ` --data '${payload}'` : ''}\`. Then inspect the run with \`npx n8nac execution get <id> --include-data\`. The production URL needs NO editor arming — never tell the user to run/arm it manually.`, { agentType: 'n8n-autopilot:n8n-tester', schema: TEST_SCHEMA, phase: 'Test' })
    if (test.outcome !== 'classB') break
    tCycle++
    if (tCycle > 3) { log('Class B persists after 3 cycles'); break }
    log(`Class B (cycle ${tCycle}) -> fix -> revalidate -> repush -> reactivate`)
    await agent(`Fix these Class-B wiring errors in ${FILE}:\n${test.errors.map((e) => '- ' + e).join('\n')}`, { agentType: 'n8n-autopilot:n8n-author', schema: AUTHOR_SCHEMA, model: 'opus', phase: 'Test' })
    const rv = await agent(`Validate the file: ${FILE}`, { agentType: 'n8n-autopilot:n8n-validator', schema: VALIDATE_SCHEMA, phase: 'Test' })
    if (!rv.passed) { test = { outcome: 'classB', executionId: null, executionStatus: null, errors: rv.errors, outputSample: '' }; break }
    const rp = await agent(`Deploy + verify the file: ${FILE}.`, { agentType: 'n8n-autopilot:n8n-deployer', schema: PUSH_SCHEMA, phase: 'Test' })
    if (!rp.pushed || !rp.verified) { test = { outcome: 'error', executionId: null, executionStatus: null, errors: [rp.error || 'repush failed'], outputSample: '' }; break }
    await agent(`Re-activate workflow ${WID}: \`npx n8nac workflow activate ${WID}\`.`, { agentType: 'n8n-autopilot:n8n-tester', schema: ACTIVATE_SCHEMA, phase: 'Test' })
  }
} else {
  test = { outcome: 'non-http', triggerType: tp.triggerType, presentUrl: tp.presentUrl }
  log(`Non-HTTP trigger (${tp.triggerType}) — not auto-fireable via HTTP`)
}

// status = success ONLY on a real, inspected, successful execution. Everything else ESCALATES.
let status = 'failed', attention = ''
if (test && test.outcome === 'success' && test.executionId) {
  status = 'success'
} else if (test && test.outcome === 'classA') {
  attention = `Class A — missing credentials/model (${(cred.missing || []).join(', ') || 'see workflow'}); workflow could NOT execute. Provide the credential, then re-run.`
} else if (test && test.outcome === 'non-http') {
  attention = `Trigger '${tp.triggerType}' cannot be HTTP-fired; this pipeline could not prove a successful execution headlessly.`
} else {
  attention = test ? `No successful execution (outcome=${test.outcome}). ${test.outputSample || (test.errors || []).join('; ')}` : 'No test result.'
}

return { status, mode: 'greenfield', workflowName: plan.workflowName, workflowId: WID, filePath: FILE, url: tp.presentUrl, triggerType: tp.triggerType, hasMcpTrigger: plan.hasMcpTrigger, activated, missingSchemas, credentialsMissing: cred.allPresent ? [] : cred.missing, validateCycles: vCycle, reviewWarnings: rev ? rev.warnings : [], test, attention }
