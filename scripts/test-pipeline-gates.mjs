#!/usr/bin/env node
// Gate regression check for the build-workflow-v2 pipelines.
//
// The scripts are Workflow-runtime modules: top-level `await`, top-level `return`, and injected
// globals (agent/log/phase/...). We reproduce that here by wrapping the body in an async function
// and passing scripted agent stubs — so the GATE LOGIC is exercised without spawning a single agent.
//
// Covers the two branches that burned a 3-hour session (issues #33, #34):
//   1. no-op patch  -> success + noop, no deploy call
//   2. classB + author says "no defect" -> ONE fix attempt, no repush, outcome test-data-gap
//
// Run: node scripts/test-pipeline-gates.mjs
import { readFileSync } from 'node:fs'
import assert from 'node:assert/strict'

const runScript = async (file, { args, reply }) => {
  const src = readFileSync(new URL(`../skills/build-workflow-v2/${file}`, import.meta.url), 'utf8')
    .replace(/^export const meta/m, 'const meta')
  const calls = []
  const agent = async (prompt, opts = {}) => {
    calls.push({ phase: opts.phase, agentType: opts.agentType, prompt })
    const r = reply({ prompt, opts, calls })
    if (r === undefined) throw new Error(`test stub has no reply for ${opts.agentType} @ ${opts.phase}`)
    return r
  }
  const body = new Function(
    'agent', 'parallel', 'pipeline', 'log', 'phase', 'args', 'workflow', 'budget',
    `return (async () => {\n${src}\n})()`
  )
  const result = await body(
    agent,
    async (thunks) => Promise.all(thunks.map((t) => t())),
    async () => [],
    () => {},
    () => {},
    args,
    async () => ({}),
    { total: null, spent: () => 0, remaining: () => Infinity }
  )
  return { result, calls }
}

// --- 1. no-op patch is a success, not a stack-halting failure -------------------------
{
  const { result, calls } = await runScript('edit.workflow.js', {
    args: { target: 'WF1', change: 'add the ACL branch' },
    reply: ({ opts }) => {
      switch (opts.agentType) {
        case 'n8n-autopilot:n8n-comprehender':
          return { workflowId: 'WF1', filePath: '/x/a.workflow.ts', triggerType: 'schedule', localPresent: true, changeSite: 'node X', newNodeTypes: [] }
        case 'n8n-autopilot:n8n-author':
          return { filePath: '/x/a.workflow.ts', written: false, noChangeNeeded: true, summary: 'already present' }
        default:
          return undefined // any validator/deployer/tester call = regression
      }
    },
  })
  assert.equal(result.status, 'success', 'no-op edit must not be a failure')
  assert.equal(result.noop, true)
  assert.equal(result.workflowId, 'WF1')
  assert.ok(!calls.some((c) => c.agentType.includes('deployer')), 'no-op must not deploy')
  assert.ok(!calls.some((c) => c.agentType.includes('validator')), 'no-op must not validate')
  console.log('ok 1 — no-op patch -> success+noop, no deploy/validate')
}

// --- 2. classB + "not a defect" verdict stops the loop after ONE fix attempt ----------
{
  const { result, calls } = await runScript('edit.workflow.js', {
    args: { target: 'WF2', change: 'rewire the crawl' },
    reply: ({ opts, prompt }) => {
      switch (opts.agentType) {
        case 'n8n-autopilot:n8n-comprehender':
          return { workflowId: 'WF2', filePath: '/x/b.workflow.ts', triggerType: 'webhook', localPresent: true, changeSite: 'links', newNodeTypes: [] }
        case 'n8n-autopilot:n8n-author':
          // Patch phase writes; the Test-phase fix call reports "not a defect in the file".
          return prompt.startsWith('Fix these Class-B')
            ? { filePath: '/x/b.workflow.ts', written: false, noChangeNeeded: true, summary: 'placeholder ids in payload, file is fine' }
            : { filePath: '/x/b.workflow.ts', written: true, summary: 'rewired' }
        case 'n8n-autopilot:n8n-validator': return { passed: true, errors: [] }
        case 'n8n-autopilot:workflow-reviewer': return { blockers: [], warnings: [] }
        case 'n8n-autopilot:n8n-deployer': return { pushed: true, verified: true, workflowId: 'WF2', driftStatus: 'TRACKED', error: null }
        case 'n8n-autopilot:n8n-tester':
          return prompt.startsWith('Classify')
            ? { triggerType: 'webhook', testable: true, suggestedPayload: '{"drive_id":"example-id"}', presentUrl: 'u' }
            : { outcome: 'classB', executionId: '1', executionStatus: 'error', errors: ['HTTP 400 invalidRequest'], outputSample: '' }
        default: return undefined
      }
    },
  })
  const fixCalls = calls.filter((c) => c.prompt.startsWith('Fix these Class-B'))
  const deploys = calls.filter((c) => c.agentType.includes('deployer'))
  const tests = calls.filter((c) => c.agentType.includes('tester') && !c.prompt.startsWith('Classify'))
  assert.equal(result.test.outcome, 'test-data-gap', 'author verdict must reclassify the outcome')
  assert.equal(result.proven, false)
  assert.equal(result.status, 'success', 'build gates were green — not a build failure')
  assert.equal(fixCalls.length, 1, `expected exactly 1 fix attempt, got ${fixCalls.length}`)
  assert.equal(deploys.length, 1, `expected no repush after the verdict, got ${deploys.length} deploys`)
  assert.equal(tests.length, 1, `expected no retest after the verdict, got ${tests.length} tests`)
  console.log('ok 2 — classB + no-defect verdict -> 1 fix, no repush/retest, test-data-gap')
}

// --- 3. same verdict rule on the greenfield path (build.workflow.js) -----------------
{
  const { result, calls } = await runScript('build.workflow.js', {
    args: { description: 'crawl a folder via webhook' },
    reply: ({ opts, prompt }) => {
      switch (opts.agentType) {
        case 'n8n-autopilot:n8n-researcher':
          return { workflowName: 'Crawler', triggerType: 'webhook', nodes: [{ type: 'n8n-nodes-base.httpRequest', purpose: 'graph' }], hasMcpTrigger: false, syncFolder: '/x', suggestedTestData: '{"drive_id":"example-id"}' }
        case 'n8n-autopilot:n8n-node-verifier':
          return { type: 'n8n-nodes-base.httpRequest', found: true, typeVersion: 4, params: [{ name: 'url' }] }
        case 'n8n-autopilot:n8n-author':
          return prompt.startsWith('Fix these Class-B')
            ? { filePath: '/x/c.workflow.ts', written: false, noChangeNeeded: true, summary: 'placeholder ids, file is fine' }
            : { filePath: '/x/c.workflow.ts', written: true, summary: 'authored' }
        case 'n8n-autopilot:n8n-validator': return { passed: true, errors: [] }
        case 'n8n-autopilot:workflow-reviewer': return { blockers: [], warnings: [] }
        case 'n8n-autopilot:n8n-deployer': return { pushed: true, verified: true, workflowId: 'WF3', driftStatus: 'TRACKED', error: null }
        case 'n8n-autopilot:n8n-tester':
          if (prompt.startsWith('Classify')) return { triggerType: 'webhook', testable: true, suggestedPayload: '{"drive_id":"example-id"}', presentUrl: 'u' }
          if (prompt.startsWith('Check credential')) return { allPresent: true, missing: [] }
          if (prompt.startsWith('Activate') || prompt.startsWith('Re-activate')) return { activated: true, error: null }
          return { outcome: 'classB', executionId: '9', executionStatus: 'error', errors: ['HTTP 400 invalidRequest'], outputSample: '' }
        default: return undefined
      }
    },
  })
  assert.equal(result.test.outcome, 'test-data-gap')
  assert.equal(result.status, 'success')
  assert.equal(result.proven, false)
  assert.equal(calls.filter((c) => c.prompt.startsWith('Fix these Class-B')).length, 1)
  assert.equal(calls.filter((c) => c.agentType.includes('deployer')).length, 1, 'no repush after the verdict')
  console.log('ok 3 — greenfield: same verdict rule, success+proven:false, no repush')
}

// --- 4. warnings are a FAILED gate, even with passed:true --------------------------
// n8nac 2.5.0 returns `"valid": true, "errors": []` together with exit code 1 when a node carries
// unknown parameters. n8n silently drops those keys, so the node ships unconfigured. A validator
// that reports passed:true with warnings must NOT get the workflow deployed.
{
  const { result, calls } = await runScript('build.workflow.js', {
    args: { description: 'crawl a folder via webhook' },
    reply: ({ opts, prompt }) => {
      switch (opts.agentType) {
        case 'n8n-autopilot:n8n-researcher':
          return { workflowName: 'Crawler', triggerType: 'webhook', nodes: [{ type: 'n8n-nodes-base.set', purpose: 'map' }], hasMcpTrigger: false, syncFolder: '/x', suggestedTestData: '{}' }
        case 'n8n-autopilot:n8n-node-verifier':
          return { type: 'n8n-nodes-base.set', found: true, typeVersion: 3.4, params: [{ name: 'assignments' }] }
        case 'n8n-autopilot:n8n-author':
          return { filePath: '/x/d.workflow.ts', written: true, summary: 'authored' }
        case 'n8n-autopilot:n8n-validator':
          return { passed: true, errors: [], warnings: ['Unknown parameter: "assignmentsXYZ". This might be a typo or deprecated parameter.'] }
        case 'n8n-autopilot:workflow-reviewer': return { blockers: [], warnings: [] }
        case 'n8n-autopilot:n8n-deployer': return { pushed: true, verified: true, workflowId: 'WF4', driftStatus: 'TRACKED', error: null }
        default: return undefined
      }
    },
  })
  assert.equal(result.status, 'failed', 'a warning-only validation must fail the gate')
  assert.equal(result.stage, 'validate')
  assert.ok(result.errors.some((e) => e.includes('assignmentsXYZ')), 'the warning must reach the caller as an error')
  assert.equal(calls.filter((c) => c.agentType.includes('deployer')).length, 0, 'must never deploy on warnings')
  console.log('ok 4 — validator warnings block the gate, no deploy')
}

// --- 5. schedule trigger is proven by a PINNED native-MCP test, never activated ---------
// Before 5.4.0 every non-HTTP trigger ended as "non-http / prove it by hand", and HTTP triggers
// needed activate -> production URL -> self-inflicted active-flag drift. Default now: the instance
// runs the pushed draft on pin data (prepare_test_pin_data -> test_workflow), no side effects.
{
  const { result, calls } = await runScript('build.workflow.js', {
    args: { description: 'nightly digest' },
    reply: ({ opts, prompt }) => {
      switch (opts.agentType) {
        case 'n8n-autopilot:n8n-researcher':
          return { workflowName: 'Digest', triggerType: 'schedule', nodes: [{ type: 'n8n-nodes-base.set', purpose: 'map' }], hasMcpTrigger: false, syncFolder: '/x' }
        case 'n8n-autopilot:n8n-node-verifier':
          return { type: 'n8n-nodes-base.set', found: true, typeVersion: 3.4, params: [{ name: 'assignments' }] }
        case 'n8n-autopilot:n8n-author': return { filePath: '/x/e.workflow.ts', written: true, summary: 'authored' }
        case 'n8n-autopilot:n8n-validator': return { passed: true, errors: [], warnings: [] }
        case 'n8n-autopilot:workflow-reviewer': return { blockers: [], warnings: [] }
        case 'n8n-autopilot:n8n-deployer': return { pushed: true, verified: true, workflowId: 'WF5', driftStatus: 'TRACKED', error: null }
        case 'n8n-autopilot:n8n-tester':
          if (prompt.startsWith('Classify')) return { triggerType: 'schedule', testable: false, suggestedPayload: null, presentUrl: 'u' }
          if (prompt.startsWith('Check credential')) return { allPresent: true, missing: [] }
          if (prompt.includes('prepare_test_pin_data') && prompt.includes('test_workflow') && !prompt.includes('execute_workflow')) return { outcome: 'success', executionId: '42', executionStatus: 'success', errors: [], outputSample: 'digest built' }
          return undefined
        default: return undefined
      }
    },
  })
  assert.equal(result.status, 'success')
  assert.equal(result.proven, true, 'a schedule workflow is proven by a real MCP execution')
  assert.equal(result.test.executionId, '42')
  assert.equal(calls.filter((c) => c.prompt.startsWith('Activate')).length, 0, 'never activates to test')
  console.log('ok 5 — schedule trigger proven by pinned test_workflow, no activation, no live call')
}

// --- 6. MCP path unavailable fails loudly, never passes as unprovable ------------------
{
  const { result } = await runScript('build.workflow.js', {
    args: { description: 'form intake' },
    reply: ({ opts, prompt }) => {
      switch (opts.agentType) {
        case 'n8n-autopilot:n8n-researcher':
          return { workflowName: 'Intake', triggerType: 'form', nodes: [{ type: 'n8n-nodes-base.set', purpose: 'map' }], hasMcpTrigger: false, syncFolder: '/x' }
        case 'n8n-autopilot:n8n-node-verifier':
          return { type: 'n8n-nodes-base.set', found: true, typeVersion: 3.4, params: [{ name: 'assignments' }] }
        case 'n8n-autopilot:n8n-author': return { filePath: '/x/f.workflow.ts', written: true, summary: 'authored' }
        case 'n8n-autopilot:n8n-validator': return { passed: true, errors: [], warnings: [] }
        case 'n8n-autopilot:workflow-reviewer': return { blockers: [], warnings: [] }
        case 'n8n-autopilot:n8n-deployer': return { pushed: true, verified: true, workflowId: 'WF6', driftStatus: 'TRACKED', error: null }
        case 'n8n-autopilot:n8n-tester':
          if (prompt.startsWith('Classify')) return { triggerType: 'form', testable: true, suggestedPayload: '{"name":"a"}', presentUrl: 'u' }
          if (prompt.startsWith('Check credential')) return { allPresent: true, missing: [] }
          return { outcome: 'mcp-unavailable', executionId: null, executionStatus: null, errors: ['Workflow is not available in MCP. Enable MCP access in workflow settings.'], outputSample: '' }
        default: return undefined
      }
    },
  })
  assert.equal(result.status, 'failed', 'an unreachable test path is a failure, not an unprovable pass')
  assert.equal(result.proven, false)
  assert.ok(result.attention.includes('availableInMCP'))
  console.log('ok 6 — mcp-unavailable fails the build with the setup hint')
}

// --- 7. caller-supplied real test data -> LIVE execute_workflow (manual = pushed draft) ---
{
  const { result, calls } = await runScript('build.workflow.js', {
    args: { description: 'lead intake webhook', testData: '{"email":"max@example.org"}' },
    reply: ({ opts, prompt }) => {
      switch (opts.agentType) {
        case 'n8n-autopilot:n8n-researcher':
          return { workflowName: 'Leads', triggerType: 'webhook', nodes: [{ type: 'n8n-nodes-base.set', purpose: 'map' }], hasMcpTrigger: false, syncFolder: '/x' }
        case 'n8n-autopilot:n8n-node-verifier':
          return { type: 'n8n-nodes-base.set', found: true, typeVersion: 3.4, params: [{ name: 'assignments' }] }
        case 'n8n-autopilot:n8n-author': return { filePath: '/x/g.workflow.ts', written: true, summary: 'authored' }
        case 'n8n-autopilot:n8n-validator': return { passed: true, errors: [], warnings: [] }
        case 'n8n-autopilot:workflow-reviewer': return { blockers: [], warnings: [] }
        case 'n8n-autopilot:n8n-deployer': return { pushed: true, verified: true, workflowId: 'WF7', driftStatus: 'TRACKED', error: null }
        case 'n8n-autopilot:n8n-tester':
          if (prompt.startsWith('Classify')) return { triggerType: 'webhook', testable: true, suggestedPayload: '{}', presentUrl: 'u' }
          if (prompt.startsWith('Check credential')) return { allPresent: true, missing: [] }
          if (prompt.includes('execute_workflow') && prompt.includes('executionMode="manual"') && prompt.includes('max@example.org')) return { outcome: 'success', executionId: '7', executionStatus: 'success', errors: [], outputSample: 'lead stored' }
          return undefined
        default: return undefined
      }
    },
  })
  assert.equal(result.proven, true)
  assert.equal(calls.filter((c) => c.prompt.includes('test_workflow')).length, 0, 'real data -> live run, not pinned')
  console.log('ok 7 — caller test data triggers a LIVE execute_workflow on the pushed draft')
}

// --- 8. a push-lint BLOCK is a fix loop, not a deploy failure --------------------------
// The hook inside `n8nac push` refuses the file (instance node version / version-gated param /
// no error strategy / masked error). Its BLOCK lines are the defect list: author fixes, validator
// re-checks, deployer pushes again. A drift block still ends the build.
{
  let deploys = 0
  const { result, calls } = await runScript('build.workflow.js', {
    args: { description: 'lead intake' },
    reply: ({ opts, prompt }) => {
      switch (opts.agentType) {
        case 'n8n-autopilot:n8n-researcher':
          return { workflowName: 'Leads', triggerType: 'webhook', nodes: [{ type: 'n8n-nodes-base.httpRequest', purpose: 'crm' }], hasMcpTrigger: false, syncFolder: '/x', errorWorkflowId: 'ERR1' }
        case 'n8n-autopilot:n8n-node-verifier':
          return { type: 'n8n-nodes-base.httpRequest', found: true, typeVersion: 4.2, params: [{ name: 'url' }] }
        case 'n8n-autopilot:n8n-author':
          return { filePath: '/x/h.workflow.ts', written: true, summary: prompt.startsWith('The push-lint gate blocked') ? 'set errorWorkflow' : 'authored' }
        case 'n8n-autopilot:n8n-validator': return { passed: true, errors: [], warnings: [] }
        case 'n8n-autopilot:workflow-reviewer': return { blockers: [], warnings: [] }
        case 'n8n-autopilot:n8n-deployer':
          deploys++
          return deploys === 1
            ? { pushed: false, verified: false, workflowId: null, driftStatus: null, blockedBy: 'push-lint', error: '[push-lint] BLOCKED — design-quality lint failed\nBLOCK  no-error-strategy  -  top-level workflow calls external services (CRM) but has no error strategy' }
            : { pushed: true, verified: true, workflowId: 'WF8', driftStatus: 'TRACKED', blockedBy: null, error: null }
        case 'n8n-autopilot:n8n-tester':
          if (prompt.startsWith('Classify')) return { triggerType: 'webhook', testable: true, suggestedPayload: '{}', presentUrl: 'u' }
          if (prompt.startsWith('Check credential')) return { allPresent: true, missing: [] }
          return { outcome: 'success', executionId: '8', executionStatus: 'success', errors: [], outputSample: 'ok' }
        default: return undefined
      }
    },
  })
  assert.equal(result.status, 'success', 'a fixed lint block must not fail the build')
  assert.equal(result.workflowId, 'WF8')
  assert.equal(deploys, 2, 'exactly one redeploy after the fix')
  assert.equal(calls.filter((c) => c.prompt.startsWith('The push-lint gate blocked')).length, 1, 'one lint fix')
  assert.ok(calls.some((c) => c.agentType.includes('author') && c.prompt.includes('errorWorkflow: "ERR1"')), 'author is told the error-handler id')
  console.log('ok 8 — push-lint block -> author fix -> validate -> redeploy -> success')
}

// --- 9. a drift block is NOT a lint block: no fix loop, build fails at deploy --------------
{
  let deploys = 0
  const { result } = await runScript('build.workflow.js', {
    args: { description: 'lead intake' },
    reply: ({ opts, prompt }) => {
      switch (opts.agentType) {
        case 'n8n-autopilot:n8n-researcher':
          return { workflowName: 'Leads', triggerType: 'webhook', nodes: [{ type: 'n8n-nodes-base.set', purpose: 'map' }], hasMcpTrigger: false, syncFolder: '/x' }
        case 'n8n-autopilot:n8n-node-verifier': return { type: 'n8n-nodes-base.set', found: true, typeVersion: 3.4, params: [{ name: 'assignments' }] }
        case 'n8n-autopilot:n8n-author': return { filePath: '/x/i.workflow.ts', written: true, summary: 'authored' }
        case 'n8n-autopilot:n8n-validator': return { passed: true, errors: [], warnings: [] }
        case 'n8n-autopilot:workflow-reviewer': return { blockers: [], warnings: [] }
        case 'n8n-autopilot:n8n-deployer':
          deploys++
          return { pushed: false, verified: false, workflowId: null, driftStatus: 'MODIFIED_BOTH', blockedBy: 'push-gate', error: '[push-gate] BLOCKED — remote drift detected' }
        default: return undefined
      }
    },
  })
  assert.equal(result.status, 'failed')
  assert.equal(result.stage, 'deploy')
  assert.equal(result.blockedBy, 'push-gate')
  assert.equal(deploys, 1, 'no retry on a drift block')
  console.log('ok 9 — push-gate drift block fails at deploy without a fix loop')
}

// --- 10. greenfield author no-op with an existing file continues to validate/deploy (#58, #87) ---
{
  const { result, calls } = await runScript('build.workflow.js', {
    args: { description: 'nightly digest' },
    reply: ({ opts, prompt }) => {
      switch (opts.agentType) {
        case 'n8n-autopilot:n8n-researcher':
          return { workflowName: 'Digest', triggerType: 'schedule', nodes: [{ type: 'n8n-nodes-base.set', purpose: 'map' }], hasMcpTrigger: false, syncFolder: '/x' }
        case 'n8n-autopilot:n8n-node-verifier': return { type: 'n8n-nodes-base.set', found: true, typeVersion: 3.4, params: [{ name: 'assignments' }] }
        case 'n8n-autopilot:n8n-author': return { filePath: '/x/j.workflow.ts', written: false, noChangeNeeded: true, summary: 'file already exists and matches the request' }
        case 'n8n-autopilot:n8n-validator': return { passed: true, errors: [], warnings: [] }
        case 'n8n-autopilot:workflow-reviewer': return { blockers: [], warnings: [] }
        case 'n8n-autopilot:n8n-deployer': return { pushed: true, verified: true, workflowId: 'WF10', driftStatus: 'TRACKED', blockedBy: null, error: null }
        case 'n8n-autopilot:n8n-tester':
          if (prompt.startsWith('Classify')) return { triggerType: 'schedule', testable: false, suggestedPayload: null, presentUrl: 'u' }
          if (prompt.startsWith('Check credential')) return { allPresent: true, missing: [] }
          return { outcome: 'success', executionId: '10', executionStatus: 'success', errors: [], outputSample: 'ok' }
        default: return undefined
      }
    },
  })
  assert.equal(result.status, 'success', 'author no-op on an existing file is not a build failure')
  assert.equal(result.workflowId, 'WF10')
  assert.ok(calls.some((c) => c.agentType.includes('validator')), 'the existing file is still validated')
  assert.ok(calls.some((c) => c.agentType.includes('deployer')), 'and deployed')
  console.log('ok 10 — greenfield author no-op (resume) continues through validate/deploy')
}

console.log('\nall pipeline-gate checks passed')
