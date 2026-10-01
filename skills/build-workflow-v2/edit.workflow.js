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
const AUTHOR_SCHEMA = { type: 'object', required: ['filePath', 'written'], additionalProperties: false, properties: { filePath: { type: 'string' }, written: { type: 'boolean' }, noChangeNeeded: { type: 'boolean', description: 'true when the requested change is ALREADY fully present / the reported error is not a defect in this file — a deliberate no-op, not a failure' }, summary: { type: 'string' } } }
// `passed` mirrors the CLI EXIT CODE, not the JSON `valid` field (n8nac 2.5.0: `"valid": true` +
// 8 unknown-parameter warnings + exit 1). Warnings gate here — see build.workflow.js for the measurement.
const VALIDATE_SCHEMA = { type: 'object', required: ['passed', 'errors', 'warnings'], additionalProperties: false, properties: { passed: { type: 'boolean' }, errors: { type: 'array', items: { type: 'string' } }, warnings: { type: 'array', items: { type: 'string' } } } }
const vIssues = (r) => [...(r.errors || []), ...(r.warnings || [])]
const REVIEW_SCHEMA = { type: 'object', required: ['blockers', 'warnings'], additionalProperties: false, properties: { blockers: { type: 'array', items: { type: 'string' } }, warnings: { type: 'array', items: { type: 'string' } } } }
// `blockedBy`: the PreToolUse gate that refused the push ('push-lint' | 'push-gate' | 'enforce-env' | null).
const PUSH_SCHEMA = { type: 'object', required: ['pushed', 'verified'], additionalProperties: false, properties: { pushed: { type: 'boolean' }, verified: { type: 'boolean' }, workflowId: { type: ['string', 'null'] }, driftStatus: { type: ['string', 'null'] }, blockedBy: { type: ['string', 'null'] }, error: { type: ['string', 'null'] } } }
const TESTPLAN_SCHEMA = { type: 'object', required: ['triggerType', 'testable'], additionalProperties: false, properties: { triggerType: { type: 'string' }, testable: { type: 'boolean' }, suggestedPayload: { type: ['string', 'null'] }, presentUrl: { type: ['string', 'null'] } } }
const TEST_SCHEMA = { type: 'object', required: ['outcome'], additionalProperties: false, properties: { outcome: { type: 'string', enum: ['success', 'classA', 'classB', 'test-data-gap', 'runtime-state', 'mcp-unavailable', 'error'] }, executionId: { type: ['string', 'null'] }, executionStatus: { type: ['string', 'null'] }, errors: { type: 'array', items: { type: 'string' } }, outputSample: { type: 'string' } } }

// args arrives as a JSON STRING from the Workflow runtime — parse defensively.
const A = (() => { if (typeof args !== 'string') return args || {}; try { return JSON.parse(args) } catch (e) { return {} } })()
const target = A.target || A.workflowId || A.name || ''
const change = A.change || A.description || ''
const userTestData = A.testData || ''
// Stack driver sets this: the stack proves the use case ONCE end-to-end after all sub-workflows
// are deployed and activated bottom-up, instead of firing every sub-workflow with synthetic data.
const deferTest = A.deferTest === true
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
  `Apply this change to the EXISTING workflow file ${FILE}:\n"""${change}"""\nChange site (from comprehension): ${ctx.changeSite}\nPreserve everything else (id, name, unrelated nodes/links). Verified contracts for any new node types:\n${contractBlock}\nDo NOT change the @workflow id. Use Edit (not full rewrite) where possible.\nIf the requested change is ALREADY fully present in the file, change nothing and return written=false + noChangeNeeded=true with the evidence in summary — that is a valid outcome, not a failure.`,
  { agentType: 'n8n-autopilot:n8n-author', schema: AUTHOR_SCHEMA, model: 'opus', phase: 'Patch' },
  { written: false, summary: 'patch agent produced no output' }
)
if (!patched.written) {
  // A change that is already present is DONE, not failed. Comprehend refreshed the file to the
  // remote base and nothing was written, so local == remote — validate/deploy/test would only
  // re-prove an untouched workflow. Marking this 'failed' HALTed whole stack runs (4 in one run).
  if (patched.noChangeNeeded) {
    log('No change needed — already present. Skipping validate/deploy/test (file == remote base).')
    return { status: 'success', mode: 'edit', noop: true, proven: false, workflowId: WID, filePath: FILE, url: null, triggerType: ctx.triggerType, detail: patched.summary || 'change already present', attention: 'No-op: the requested change was already in the file; nothing deployed.' }
  }
  return { status: 'failed', stage: 'patch', detail: patched.summary || 'no edit written', filePath: FILE }
}

// ===== PHASE 4 — VALIDATE GATE =====
phase('Validate')
let vRes = null, vCycle = 0
while (true) {
  vRes = await safe(`Validate the file: ${FILE}`, { agentType: 'n8n-autopilot:n8n-validator', schema: VALIDATE_SCHEMA, phase: 'Validate' }, { passed: false, errors: ['validator produced no output'], warnings: [] })
  if (vRes.passed && vIssues(vRes).length === 0) { log(`Validate passed (cycle ${vCycle})`); break }
  vCycle++
  if (vCycle > 3) return { status: 'failed', stage: 'validate', cycles: vCycle - 1, errors: vIssues(vRes), filePath: FILE }
  log(`Validate failed (cycle ${vCycle}): ${vIssues(vRes).length} issue(s) -> fixing`)
  await safe(`Fix these validation errors in ${FILE} (preserve the intended change):\n${vIssues(vRes).map((e) => '- ' + e).join('\n')}`, { agentType: 'n8n-autopilot:n8n-author', schema: AUTHOR_SCHEMA, model: 'opus', phase: 'Validate' }, {})
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
// A push-lint block (node versions, version-gated params, error handling, expressions) is a fix
// loop, not a deploy failure — the hook's BLOCK lines are the defect list. Drift stays a failure.
phase('Deploy')
let pushRes = null, lCycle = 0
while (true) {
  pushRes = await safe(`Deploy + verify the file: ${FILE} (drift-check first; do NOT bypass the push-gate). If a PreToolUse hook blocks the push, return pushed=false, blockedBy="<gate tag>" and the hook's BLOCK lines verbatim in error.`, { agentType: 'n8n-autopilot:n8n-deployer', schema: PUSH_SCHEMA, phase: 'Deploy' }, { pushed: false, verified: false, workflowId: null, driftStatus: null, blockedBy: null, error: 'deployer produced no output' })
  if (pushRes.pushed && pushRes.verified) break
  const lintBlock = pushRes.blockedBy === 'push-lint' || /\[push-lint\] BLOCKED/.test(pushRes.error || '')
  if (!lintBlock) {
    // Drift here means remote changed DURING this run (we refreshed at comprehend). Surface, do not clobber.
    return { status: 'failed', stage: 'deploy', driftStatus: pushRes.driftStatus, blockedBy: pushRes.blockedBy || null, error: pushRes.error || 'push/verify failed', filePath: FILE, hint: pushRes.driftStatus ? 'Remote changed during the edit run. Re-run the edit flow to pick up the new base.' : undefined }
  }
  lCycle++
  if (lCycle > 3) return { status: 'failed', stage: 'lint', cycles: lCycle - 1, error: pushRes.error, filePath: FILE }
  log(`push-lint blocked the push (cycle ${lCycle}) -> fixing the BLOCK findings`)
  const fix = await safe(`The push-lint gate blocked the push of ${FILE}. Fix EXACTLY these findings (rule · node · message), preserving the intended change and everything unrelated:\n${pushRes.error}\nRules: no-error-strategy → set settings.errorWorkflow (grep .n8n-autopilot/instance-cache.json for an errorTrigger workflow) or wire an error output; masked-error → route the node's main output into an If that tests $json.error, or use onError: continueErrorOutput + error branch; param-version → move the parameter to where this typeVersion keeps it (npx n8nac skills node-info <type> --json) or use the version that has it; node/version not on the instance → a version the instance lists.`, { agentType: 'n8n-autopilot:n8n-author', schema: AUTHOR_SCHEMA, model: 'opus', phase: 'Deploy' }, { written: false, summary: 'author produced no output' })
  if (!fix.written) return { status: 'failed', stage: 'lint', cycles: lCycle, error: `${pushRes.error}\nauthor: ${fix.summary || 'no fix written'}`, filePath: FILE }
  const rv = await safe(`Validate the file: ${FILE}`, { agentType: 'n8n-autopilot:n8n-validator', schema: VALIDATE_SCHEMA, phase: 'Deploy' }, { passed: false, errors: ['validator produced no output'], warnings: [] })
  if (!rv.passed || vIssues(rv).length) return { status: 'failed', stage: 'lint', cycles: lCycle, errors: vIssues(rv), filePath: FILE }
}
log(`Pushed + verified. workflowId=${WID}${lCycle ? ` (after ${lCycle} lint fix cycle(s))` : ''}`)

// ===== PHASE 6 — TEST =====
phase('Test')
const tp = await agent(`Classify how workflow ${WID} can be tested (test-plan + present URL).`, { agentType: 'n8n-autopilot:n8n-tester', schema: TESTPLAN_SCHEMA, phase: 'Test' })
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
if (deferTest) {
  test = { outcome: 'deferred', triggerType: tp.triggerType, presentUrl: tp.presentUrl }
  log('deferTest — stack driver owns activation (bottom-up) + the single E2E proof')
} else {
  let tCycle = 0
  while (true) {
    test = await agent(mcpTestPrompt(), { agentType: 'n8n-autopilot:n8n-tester', schema: TEST_SCHEMA, phase: 'Test' })
    if (test.outcome !== 'classB') break
    tCycle++
    if (tCycle > 3) { log('Class B persists after 3 cycles'); break }
    log(`Class B (cycle ${tCycle}) -> fix -> revalidate -> repush`)
    // Same rule as greenfield: the author decides whether the FILE is defective. A "no defect"
    // verdict ends the loop — repushing identical bytes reproduces the identical error.
    const fix = await agent(`Fix these Class-B wiring errors in ${FILE}:\n${test.errors.map((e) => '- ' + e).join('\n')}\nIf this is NOT a defect in the file (e.g. an external service rejected PLACEHOLDER ids from the test payload, or the workflow needs real remote resource ids the pipeline cannot know), return written=false + noChangeNeeded=true with the reason in summary. Never invent an edit to satisfy the loop.`, { agentType: 'n8n-autopilot:n8n-author', schema: AUTHOR_SCHEMA, model: 'opus', phase: 'Test' })
    if (!fix || fix.written !== true) {
      log(`Author reports no wiring defect (cycle ${tCycle}) -> escalating as test-data-gap, no repush`)
      test = { outcome: 'test-data-gap', executionId: test.executionId, executionStatus: test.executionStatus, errors: test.errors, outputSample: (fix && fix.summary) || 'author found no defect in the file' }
      break
    }
    const rv = await agent(`Validate the file: ${FILE}`, { agentType: 'n8n-autopilot:n8n-validator', schema: VALIDATE_SCHEMA, phase: 'Test' })
    if (!rv.passed || vIssues(rv).length) { test = { outcome: 'classB', executionId: null, executionStatus: null, errors: vIssues(rv), outputSample: '' }; break }
    const rp = await agent(`Deploy + verify the file: ${FILE}.`, { agentType: 'n8n-autopilot:n8n-deployer', schema: PUSH_SCHEMA, phase: 'Test' })
    if (!rp.pushed || !rp.verified) { test = { outcome: 'error', executionId: null, executionStatus: null, errors: [rp.error || 'repush failed'], outputSample: '' }; break }
  }
}

// Build gates (validate/review/deploy) are what 'success' asserts; `proven` says whether a real
// execution was inspected. An unprovable test (deferred / manual-required / test-data-gap) leaves
// status success + attention — it is not a build failure.
const proven = !!(test && test.outcome === 'success' && test.executionId)
const attention = proven ? '' : `Deployed, but no successful execution proven (${test ? test.outcome : 'no test'}). ${test && test.outcome === 'test-data-gap' ? 'Re-test with real input.' : test && test.outcome === 'manual-required' ? `Prove it via /n8n-autopilot:test-manual ${WID}.` : test && test.outcome === 'mcp-unavailable' ? `Native MCP test path unavailable: ${(test.errors || []).join('; ')} — see docs/rules/testing.md.` : ''}`.trim()
return { status: 'success', proven, mode: 'edit', workflowId: WID, filePath: FILE, url: tp.presentUrl, triggerType: tp.triggerType, hasMcpTrigger: ctx.hasMcpTrigger, localMirrorHeld: ctx.localPresent, refreshed: ctx.refreshed, validateCycles: vCycle, reviewWarnings: rev ? rev.warnings : [], test, attention }
