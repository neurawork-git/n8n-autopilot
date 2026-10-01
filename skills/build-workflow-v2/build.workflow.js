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
    // Prior art from THIS instance, found via .n8n-autopilot/instance-cache.json. Outranks a public
    // template: it is proven against this n8n version, these credentials, this project.
    referenceWorkflow: {
      type: ['object', 'null'], required: ['id', 'file', 'settles'], additionalProperties: false,
      properties: { id: { type: 'string' }, file: { type: 'string' }, settles: { type: 'string' } },
    },
    instanceCacheUsable: { type: 'boolean' },
    // The instance's error-handler workflow (an errorTrigger workflow from instance-cache.json), for
    // settings.errorWorkflow. null when the instance has none — the author then wires error outputs.
    errorWorkflowId: { type: ['string', 'null'] },
  },
}
const NODE_CONTRACT_SCHEMA = {
  type: 'object', required: ['type', 'found', 'params'], additionalProperties: false,
  properties: {
    type: { type: 'string' }, found: { type: 'boolean' }, typeVersion: { type: ['number', 'null'] },
    params: { type: 'array', items: { type: 'object', required: ['name'], additionalProperties: false, properties: { name: { type: 'string' }, required: { type: 'boolean' } } } },
    credentialKeys: { type: 'array', items: { type: 'string' } }, notes: { type: 'string' },
    // Does this type actually run on THIS instance (per instance-cache nodeTypeUsage)? n8nac's
    // knowledge base is instance-independent, so "the node exists" and "the node exists here" are
    // different claims — and only the second one survives a push.
    provenOnInstance: { type: ['boolean', 'null'] },
  },
}
const AUTHOR_SCHEMA = { type: 'object', required: ['filePath', 'written'], additionalProperties: false, properties: { filePath: { type: 'string' }, written: { type: 'boolean' }, noChangeNeeded: { type: 'boolean', description: 'true when the requested change is ALREADY fully present / the reported error is not a defect in this file — a deliberate no-op, not a failure' }, summary: { type: 'string' } } }
// `passed` mirrors the CLI EXIT CODE, not the JSON `valid` field: n8nac 2.5.0 returns `"valid": true`
// with 8 unknown-parameter warnings and exit 1. Warnings are carried separately so THIS script decides
// the gate — an unknown param means n8n silently drops the key and the node ships unconfigured.
const VALIDATE_SCHEMA = { type: 'object', required: ['passed', 'errors', 'warnings'], additionalProperties: false, properties: { passed: { type: 'boolean' }, errors: { type: 'array', items: { type: 'string' } }, warnings: { type: 'array', items: { type: 'string' } } } }
const vIssues = (r) => [...(r.errors || []), ...(r.warnings || [])]
const REVIEW_SCHEMA = { type: 'object', required: ['blockers', 'warnings'], additionalProperties: false, properties: { blockers: { type: 'array', items: { type: 'string' } }, warnings: { type: 'array', items: { type: 'string' } } } }
// `blockedBy`: the PreToolUse gate that refused the push ('push-lint' | 'push-gate' | 'enforce-env' | null).
// A push-lint block carries the BLOCK lines in `error` and is fixable in-pipeline; the others are not.
const PUSH_SCHEMA = { type: 'object', required: ['pushed', 'verified'], additionalProperties: false, properties: { pushed: { type: 'boolean' }, verified: { type: 'boolean' }, workflowId: { type: ['string', 'null'] }, driftStatus: { type: ['string', 'null'] }, blockedBy: { type: ['string', 'null'] }, error: { type: ['string', 'null'] } } }
const TESTPLAN_SCHEMA = { type: 'object', required: ['triggerType', 'testable'], additionalProperties: false, properties: { triggerType: { type: 'string' }, testable: { type: 'boolean' }, suggestedPayload: { type: ['string', 'null'] }, presentUrl: { type: ['string', 'null'] } } }
const CRED_SCHEMA = { type: 'object', required: ['allPresent'], additionalProperties: false, properties: { allPresent: { type: 'boolean' }, missing: { type: 'array', items: { type: 'string' } } } }
const TEST_SCHEMA = { type: 'object', required: ['outcome'], additionalProperties: false, properties: { outcome: { type: 'string', enum: ['success', 'classA', 'classB', 'test-data-gap', 'runtime-state', 'mcp-unavailable', 'error'] }, executionId: { type: ['string', 'null'] }, executionStatus: { type: ['string', 'null'] }, errors: { type: 'array', items: { type: 'string' } }, outputSample: { type: 'string' } } }

// Plugin agents resolve namespaced as `<plugin>:<agent>` (proven: prp-core:* spawns in Workflow).

// args arrives as a JSON STRING from the Workflow runtime — parse defensively (bare string = description).
const A = (() => { if (typeof args !== 'string') return args || {}; try { return JSON.parse(args) } catch (e) { return { description: args } } })()
const desc = A.description || ''
const userTestData = A.testData || ''
// Stack driver sets this: activation + the E2E proof happen ONCE at stack level, bottom-up
// (n8n refuses to activate a caller whose callee is not published). Per-workflow activation
// inside a stack fails on publish ORDER, not on a broken workflow.
const deferActivation = A.deferActivation === true

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
  `Plan an n8n workflow for this request:\n"""${desc}"""\nFollow your procedure: resolve sync folder, read the instance brief and find local prior art FIRST, then the community-template lookup, node discovery (exact types), trigger classification, suggested test data.`,
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
  `Write a NEW n8n Decorator-TS workflow.\nRequest: """${desc}"""\nWorkflow name: ${plan.workflowName}\nTrigger: ${plan.triggerType}\nSync folder (write the file here): ${plan.syncFolder}\n${plan.referenceWorkflow ? `PRIOR ART ON THIS INSTANCE — read it before writing a line: ${plan.referenceWorkflow.file} (id ${plan.referenceWorkflow.id}). It settles: ${plan.referenceWorkflow.settles}. Mirror its node choices, credential blocks and wiring where they apply; justify every deviation.\n` : ''}${plan.templateId ? `Community template id ${plan.templateId} (npx n8nac skills examples download ${plan.templateId} into the sync folder) — adapt it, and where it conflicts with the prior art above, the prior art wins.` : plan.referenceWorkflow ? '' : 'No prior art and no template — author from scratch.'}\nhasMcpTrigger: ${plan.hasMcpTrigger}\nError strategy (the push-lint gate blocks a top-level workflow with external calls that has none): ${plan.errorWorkflowId ? `set settings.errorWorkflow: "${plan.errorWorkflowId}" (the instance's error handler)` : 'no error-handler workflow on this instance — wire onError: continueErrorOutput on every external node into an error branch (notify/stopAndError)'}; httpRequest nodes get retryOnFail.\nVerified node contracts (use ONLY these param names):\n${contractBlock}`,
  { agentType: 'n8n-autopilot:n8n-author', schema: AUTHOR_SCHEMA, model: 'opus', phase: 'Author' },
  { written: false, summary: 'author agent produced no output' }
)
// A deliberate no-op with an existing file is not a failure (#58, #87): on a resumed stack run the
// file is already there and already pushed — validate/deploy re-prove it instead of halting at 0/n.
if (!authored.written && !(authored.noChangeNeeded && authored.filePath))
  return { status: 'failed', stage: 'author', detail: authored.summary || 'no file written' }
const FILE = authored.filePath
log(authored.written ? `Authored ${FILE}` : `Author: ${FILE} already complete (${authored.summary || 'no-op'}) -> continuing with validate/deploy`)

// ===== PHASE 3 — VALIDATE GATE =====
phase('Validate')
let vRes = null, vCycle = 0
while (true) {
  vRes = await safe(`Validate the file: ${FILE}`, { agentType: 'n8n-autopilot:n8n-validator', schema: VALIDATE_SCHEMA, phase: 'Validate' }, { passed: false, errors: ['validator produced no output'], warnings: [] })
  if (vRes.passed && vIssues(vRes).length === 0) { log(`Validate passed (cycle ${vCycle})`); break }
  vCycle++
  if (vCycle > 3) return { status: 'failed', stage: 'validate', cycles: vCycle - 1, errors: vIssues(vRes), filePath: FILE }
  log(`Validate failed (cycle ${vCycle}): ${vIssues(vRes).length} issue(s) -> fixing`)
  await safe(`Fix these validation errors in ${FILE}:\n${vIssues(vRes).map((e) => '- ' + e).join('\n')}`, { agentType: 'n8n-autopilot:n8n-author', schema: AUTHOR_SCHEMA, model: 'opus', phase: 'Validate' }, {})
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
// The push-lint hook (instance node versions, version-gated params, error handling, expressions)
// runs INSIDE `npx n8nac push`. Its BLOCK output is the most precise defect list in the pipeline,
// so a lint block is a fix loop here — not a deploy failure. Drift blocks stay failures.
phase('Deploy')
let pushRes = null, lCycle = 0
while (true) {
  pushRes = await safe(`Deploy + verify the file: ${FILE} (drift-check first). If a PreToolUse hook blocks the push, return pushed=false, blockedBy="<gate tag>" and the hook's BLOCK lines verbatim in error.`, { agentType: 'n8n-autopilot:n8n-deployer', schema: PUSH_SCHEMA, phase: 'Deploy' }, { pushed: false, verified: false, workflowId: null, driftStatus: null, blockedBy: null, error: 'deployer produced no output' })
  if (pushRes.pushed && pushRes.verified && pushRes.workflowId) break
  const lintBlock = pushRes.blockedBy === 'push-lint' || /\[push-lint\] BLOCKED/.test(pushRes.error || '')
  if (!lintBlock) return { status: 'failed', stage: 'deploy', driftStatus: pushRes.driftStatus, blockedBy: pushRes.blockedBy || null, error: pushRes.error || 'push/verify failed or no workflowId', filePath: FILE }
  lCycle++
  if (lCycle > 3) return { status: 'failed', stage: 'lint', cycles: lCycle - 1, error: pushRes.error, filePath: FILE }
  log(`push-lint blocked the push (cycle ${lCycle}) -> fixing the BLOCK findings`)
  const fix = await safe(`The push-lint gate blocked the push of ${FILE}. Fix EXACTLY these findings (rule · node · message), preserving the intended behaviour:\n${pushRes.error}\nRules: no-error-strategy → set settings.errorWorkflow (grep .n8n-autopilot/instance-cache.json for an errorTrigger workflow) or wire an error output; masked-error → route the node's main output into an If that tests $json.error, or use onError: continueErrorOutput + error branch; param-version → move the parameter to where this typeVersion keeps it (npx n8nac skills node-info <type> --json) or use the version that has it; node/version not on the instance → a version the instance lists.`, { agentType: 'n8n-autopilot:n8n-author', schema: AUTHOR_SCHEMA, model: 'opus', phase: 'Deploy' }, { written: false, summary: 'author produced no output' })
  if (!fix.written) return { status: 'failed', stage: 'lint', cycles: lCycle, error: `${pushRes.error}\nauthor: ${fix.summary || 'no fix written'}`, filePath: FILE }
  const rv = await safe(`Validate the file: ${FILE}`, { agentType: 'n8n-autopilot:n8n-validator', schema: VALIDATE_SCHEMA, phase: 'Deploy' }, { passed: false, errors: ['validator produced no output'], warnings: [] })
  if (!rv.passed || vIssues(rv).length) return { status: 'failed', stage: 'lint', cycles: lCycle, errors: vIssues(rv), filePath: FILE }
}
const WID = pushRes.workflowId
log(`Pushed + verified. workflowId=${WID}${lCycle ? ` (after ${lCycle} lint fix cycle(s))` : ''}`)

// ===== PHASE 5 — TEST =====
phase('Test')
const tp = await agent(`Classify how workflow ${WID} can be tested (test-plan + present URL).`, { agentType: 'n8n-autopilot:n8n-tester', schema: TESTPLAN_SCHEMA, phase: 'Test' })
const cred = await agent(`Check credential readiness for workflow ${WID} (credential-required).`, { agentType: 'n8n-autopilot:n8n-tester', schema: CRED_SCHEMA, phase: 'Test' })
if (!cred.allPresent) log(`Credentials missing: ${cred.missing.join(', ')} (Class A)`)

// Test through the instance's own MCP server (n8n >= 2.20). DEFAULT = pinned test:
// prepare_test_pin_data -> test_workflow. Triggers, credentialed nodes and HTTP Request nodes run on
// pin data, so nothing external is called, every trigger type works (schedule, app triggers, error
// trigger — #10, #72) and synthetic payloads never hit real services (#59, #91). Nothing is
// activated (#37). A LIVE run (execute_workflow, manual = pushed draft, REAL side effects) happens
// only when the caller supplies real test data for a trigger the instance can feed by id.
const LIVE_TRIGGERS = ['webhook', 'chat', 'form', 'schedule', 'manual']
const liveTest = !!userTestData && LIVE_TRIGGERS.includes(tp.triggerType)
const MCP_DOWN = 'Missing MCP tools, 401, or "not available in MCP" -> outcome="mcp-unavailable" with the exact message in errors[].'
const mcpTestPrompt = () => liveTest
  ? `LIVE-test workflow ${WID} through the NATIVE n8n MCP (server \`n8n-native\`): call \`execute_workflow\` with workflowId="${WID}", executionMode="manual" (the pushed draft; do NOT activate), trigger type "${tp.triggerType}", inputs built from this caller-supplied data: ${userTestData}. Poll \`get_execution\` (includeData=true) until finished, then classify. ${MCP_DOWN}`
  : `Test workflow ${WID} through the NATIVE n8n MCP (server \`n8n-native\`) WITHOUT side effects: (1) \`prepare_test_pin_data\` for workflowId="${WID}"; (2) build pinData — realistic sample items for every schema in nodeSchemasToGenerate, [{"json": {}}] for each of nodesWithoutSchema, every item wrapped as {"json": {...}}${tp.suggestedPayload ? `; use this as the trigger item's json: ${tp.suggestedPayload}` : ''}; (3) \`test_workflow\` with workflowId + pinData; (4) \`get_execution\` with includeData=true and classify what the UNPINNED nodes did with that data. ${MCP_DOWN}`
let test = null
if (deferActivation) {
  test = { outcome: 'deferred', triggerType: tp.triggerType, presentUrl: tp.presentUrl }
  log('deferActivation — stack driver owns activation (bottom-up) + the single E2E proof')
} else {
  let tCycle = 0
  while (true) {
    test = await agent(mcpTestPrompt(), { agentType: 'n8n-autopilot:n8n-tester', schema: TEST_SCHEMA, phase: 'Test' })
    if (test.outcome !== 'classB') break
    tCycle++
    if (tCycle > 3) { log('Class B persists after 3 cycles'); break }
    log(`Class B (cycle ${tCycle}) -> fix -> revalidate -> repush -> retest (no activation)`)
    // The author is the authority on whether the FILE is defective. If it says "no defect here"
    // (e.g. the request failed on placeholder ids in the test payload), repushing the same bytes
    // and retesting reproduces the identical error — observed: 4 identical cycles. Believe it, stop.
    const fix = await agent(`Fix these Class-B wiring errors in ${FILE}:\n${test.errors.map((e) => '- ' + e).join('\n')}\nIf this is NOT a defect in the file (e.g. an external service rejected PLACEHOLDER ids from the test payload, or the workflow needs real remote resource ids the pipeline cannot know), return written=false + noChangeNeeded=true with the reason in summary. Never invent an edit to satisfy the loop.`, { agentType: 'n8n-autopilot:n8n-author', schema: AUTHOR_SCHEMA, model: 'opus', phase: 'Test' })
    if (!fix || fix.written !== true) {
      log(`Author reports no wiring defect (cycle ${tCycle}) -> escalating as test-data-gap, no repush`)
      test = { outcome: 'test-data-gap', executionId: test.executionId, executionStatus: test.executionStatus, errors: test.errors, outputSample: (fix && fix.summary) || 'author found no defect in the file' }
      break
    }
    const rv = await agent(`Validate the file: ${FILE}`, { agentType: 'n8n-autopilot:n8n-validator', schema: VALIDATE_SCHEMA, phase: 'Test' })
    if (!rv.passed || vIssues(rv).length) { test = { outcome: 'classB', executionId: null, executionStatus: null, errors: vIssues(rv), outputSample: '' }; break }
    const rp = await agent(`Deploy + verify the file: ${FILE}. Never bypass the push-gate, never \`resolve --mode keep-*\`.`, { agentType: 'n8n-autopilot:n8n-deployer', schema: PUSH_SCHEMA, phase: 'Test' })
    if (!rp.pushed || !rp.verified) { test = { outcome: 'error', executionId: null, executionStatus: null, errors: [rp.error || 'repush failed'], outputSample: '' }; break }
  }
}

// `proven` = a real, inspected, successful execution. `status` = did the BUILD get through its gates.
// Separating the two is deliberate: a schedule trigger, a deferred stack build, or a payload the
// pipeline cannot know real ids for are NOT build failures — treating them as such HALTed whole
// stacks over workflows that were green. Real blockers (missing credential, persistent wiring
// error, deploy failure) still fail.
const UNPROVABLE = ['deferred', 'test-data-gap']
let status = 'failed', proven = false, attention = ''
if (test && test.outcome === 'success' && test.executionId) {
  status = 'success'; proven = true
} else if (test && UNPROVABLE.includes(test.outcome)) {
  status = 'success'
  attention = test.outcome === 'deferred'
    ? 'Build gates green; activation + E2E proof deferred to the stack driver.'
    : `Build gates green, but the live test could not be proven with synthetic data: ${test.outputSample || (test.errors || []).join('; ')} — re-test with real input.`
} else if (test && test.outcome === 'mcp-unavailable') {
  attention = `Native n8n MCP test path unavailable: ${(test.errors || []).join('; ')} — configure native MCP for this env (npx n8nac native-mcp configure <env> --token-stdin --level 2, docs/rules/testing.md) and set availableInMCP: true in the workflow settings, then re-run.`
} else if (test && test.outcome === 'classA') {
  attention = `Class A — missing credentials/model (${(cred.missing || []).join(', ') || 'see workflow'}); workflow could NOT execute. Provide the credential, then re-run.`
} else {
  attention = test ? `No successful execution (outcome=${test.outcome}). ${test.outputSample || (test.errors || []).join('; ')}` : 'No test result.'
}

return { status, proven, mode: 'greenfield', workflowName: plan.workflowName, workflowId: WID, filePath: FILE, url: tp.presentUrl, triggerType: tp.triggerType, hasMcpTrigger: plan.hasMcpTrigger, missingSchemas, credentialsMissing: cred.allPresent ? [] : cred.missing, validateCycles: vCycle, reviewWarnings: rev ? rev.warnings : [], test, attention }
