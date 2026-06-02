export const meta = {
  name: 'build-stack-v2',
  description: 'Deterministic JS-orchestrated build of a whole n8n workflow STACK from a PRP-style use case. Decomposes into sub-workflows along known rules, fixes handover contracts, documents the architecture (mermaid), then builds each sub-workflow bottom-up via build-workflow-v2. Two modes: GREENFIELD (new stack) and EXTEND (change an existing one). Gates and build order are JS control flow, not model discretion. Roles live in agents/n8n-stack-*.md; sub-builds reuse build.workflow.js / edit.workflow.js.',
  whenToUse: 'Ship an end-to-end multi-workflow stack with decomposition, contracts, and bottom-up build enforced by code.',
  phases: [
    { title: 'Mirror', detail: 'EXTEND only: mirror-sync so the local call-graph is complete', model: 'sonnet' },
    { title: 'Comprehend', detail: 'EXTEND only: n8n-stack-comprehender reconstructs the DAG from executeWorkflow refs', model: 'sonnet' },
    { title: 'Plan', detail: 'n8n-stack-architect decompose (greenfield) / delta (extend)', model: 'opus' },
    { title: 'Document', detail: 'write docs/<stack>.architecture.md (contracts + mermaid) via n8n-author', model: 'sonnet' },
    { title: 'Build', detail: 'topological bottom-up: workflow(build.workflow.js / edit.workflow.js) per sub-workflow', model: 'opus' },
    { title: 'Report', detail: 'per-WF status + ids, update architecture doc with real workflowIds', model: 'sonnet' },
  ],
}

// ---- Schemas (the orchestrator decides; agents fill these) ----
const SUBWF = {
  type: 'object', required: ['slug', 'name', 'trigger', 'kind', 'purpose', 'dependsOn'], additionalProperties: false,
  properties: {
    slug: { type: 'string' }, name: { type: 'string' }, trigger: { type: 'string' },
    kind: { type: 'string', enum: ['leaf', 'orchestrator'] }, purpose: { type: 'string' },
    dependsOn: { type: 'array', items: { type: 'string' } },
  },
}
const HANDOVER = {
  type: 'object', required: ['from', 'to', 'inputContract', 'outputContract'], additionalProperties: false,
  properties: { from: { type: 'string' }, to: { type: 'string' }, inputContract: { type: 'string' }, outputContract: { type: 'string' } },
}
const STACKPLAN_SCHEMA = {
  type: 'object', required: ['stackSlug', 'overview', 'subWorkflows', 'handovers', 'entry'], additionalProperties: false,
  properties: {
    stackSlug: { type: 'string' }, overview: { type: 'string' },
    subWorkflows: { type: 'array', items: SUBWF }, handovers: { type: 'array', items: HANDOVER },
    entry: { type: 'string' }, buildOrderNote: { type: 'string' },
  },
}
const DELTA_SCHEMA = {
  type: 'object', required: ['newSubWorkflows', 'changedSubWorkflows', 'handoverChanges'], additionalProperties: false,
  properties: {
    newSubWorkflows: { type: 'array', items: SUBWF },
    changedSubWorkflows: { type: 'array', items: { type: 'object', required: ['slug', 'workflowId', 'changeDescription'], additionalProperties: false, properties: { slug: { type: 'string' }, workflowId: { type: 'string' }, changeDescription: { type: 'string' } } } },
    handoverChanges: { type: 'array', items: { type: 'object', required: ['from', 'to'], additionalProperties: false, properties: { from: { type: 'string' }, to: { type: 'string' }, newInputContract: { type: 'string' }, newOutputContract: { type: 'string' } } } },
    buildOrderNote: { type: 'string' },
  },
}
const CURRENTSTACK_SCHEMA = {
  type: 'object', required: ['stackSlug', 'entry', 'subWorkflows', 'edges', 'docPresent', 'missingLocal'], additionalProperties: false,
  properties: {
    stackSlug: { type: 'string' }, entry: { type: 'string' },
    subWorkflows: { type: 'array', items: { type: 'object', required: ['slug', 'workflowId', 'name', 'filePath', 'kind', 'trigger'], additionalProperties: false, properties: { slug: { type: 'string' }, workflowId: { type: 'string' }, name: { type: 'string' }, filePath: { type: 'string' }, kind: { type: 'string' }, trigger: { type: 'string' } } } },
    edges: { type: 'array', items: { type: 'object', required: ['from', 'to'], additionalProperties: false, properties: { from: { type: 'string' }, to: { type: 'string' }, observedHandover: { type: 'string' } } } },
    docPresent: { type: 'boolean' }, docDrift: { type: ['string', 'null'] },
    missingLocal: { type: 'array', items: { type: 'string' } },
  },
}
const DOCWRITE_SCHEMA = { type: 'object', required: ['written', 'filePath'], additionalProperties: false, properties: { written: { type: 'boolean' }, filePath: { type: 'string' } } }

// ---- args (arrives as JSON string from the runtime — parse defensively) ----
const A = (() => { if (typeof args !== 'string') return args || {}; try { return JSON.parse(args) } catch (e) { return { description: args } } })()
const isExtend = !!(A.change || A.mode === 'extend')
const description = A.description || ''
const change = A.change || ''
const target = A.target || ''
// Sub-orchestrator script paths are passed in by the SKILL wrapper (the script has no fs/__dirname).
const buildScript = A.buildScript || ''
const editScript = A.editScript || ''
const syncScript = A.syncScript || ''
if (!buildScript) { log('Missing args.buildScript (absolute path to build-workflow-v2/build.workflow.js).'); return { status: 'aborted', reason: 'no-build-script' } }
if (!isExtend && !description) { log('Greenfield needs args.description (the stack use-case / PRP).'); return { status: 'aborted', reason: 'no-description' } }
if (isExtend && !change) { log('Extend needs args.change (what to change).'); return { status: 'aborted', reason: 'no-change' } }
if (isExtend && !editScript) { log('Extend needs args.editScript.'); return { status: 'aborted', reason: 'no-edit-script' } }

// ---- helpers ----
// Kahn topological sort: deps first (leaves first). Returns null on cycle.
function topoSort(nodes, depsOf) {
  const indeg = new Map(nodes.map((n) => [n, 0]))
  const adj = new Map(nodes.map((n) => [n, []]))
  for (const n of nodes) for (const d of depsOf(n)) { if (!indeg.has(d)) continue; adj.get(d).push(n); indeg.set(n, indeg.get(n) + 1) }
  const q = nodes.filter((n) => indeg.get(n) === 0)
  const order = []
  while (q.length) { const n = q.shift(); order.push(n); for (const m of adj.get(n)) { indeg.set(m, indeg.get(m) - 1); if (indeg.get(m) === 0) q.push(m) } }
  return order.length === nodes.length ? order : null
}
const contractsFor = (slug, handovers) => ({
  input: handovers.filter((h) => h.to === slug).map((h) => `${h.from}→: ${h.inputContract}`).join(' | ') || '(external trigger payload)',
  output: handovers.filter((h) => h.from === slug).map((h) => `→${h.to}: ${h.outputContract}`).join(' | ') || '(stack result)',
})

// Compose the central architecture markdown DETERMINISTICALLY (mermaid + tables) — the writer agent
// only writes the bytes; no model judgement in the doc shape.
function renderArchitectureDoc(plan, idMap) {
  const mmId = (s) => s.replace(/[^a-zA-Z0-9_]/g, '_')
  const rows = plan.subWorkflows.map((s) => `| \`${s.slug}\` | ${s.name} | ${s.trigger} | ${s.kind} | ${(s.dependsOn || []).map((d) => '`' + d + '`').join(', ') || '—'} | ${idMap[s.slug] || '_(pending)_'} |`).join('\n')
  const handoverRows = plan.handovers.map((h) => `| \`${h.from}\` → \`${h.to}\` | ${h.inputContract} | ${h.outputContract} |`).join('\n')
  const mmNodes = plan.subWorkflows.map((s) => s.slug === plan.entry ? `  ${mmId(s.slug)}[["${s.name}"]]` : `  ${mmId(s.slug)}["${s.name}"]`).join('\n')
  const mmEdges = plan.handovers.map((h) => `  ${mmId(h.from)} -->|"${h.inputContract.slice(0, 40)}"| ${mmId(h.to)}`).join('\n')
  const order = topoSort(plan.subWorkflows.map((s) => s.slug), (slug) => (plan.subWorkflows.find((s) => s.slug === slug)?.dependsOn) || [])
  return `# ${plan.stackSlug} — Stack Architecture

> Generated by build-stack-v2. Single source of truth for this workflow stack.

## Overview

${plan.overview}

**Entry (owns the external trigger):** \`${plan.entry}\`

## Sub-workflows

| slug | name | trigger | kind | dependsOn | workflowId |
|---|---|---|---|---|---|
${rows}

## Handover contracts

| edge | input contract | output contract |
|---|---|---|
${handoverRows || '| — | — | — |'}

## Call graph

\`\`\`mermaid
flowchart TD
${mmNodes}
${mmEdges}
\`\`\`

## Build order (bottom-up, leaves first)

${order ? order.map((s, i) => `${i + 1}. \`${s}\``).join('\n') : '_(cycle detected — see report)_'}
`
}

async function writeDoc(content, filePath, phaseName) {
  return agent(
    `Write the following content VERBATIM to the file \`${filePath}\` (create the docs/ directory if needed). Do NOT author an n8n workflow, do NOT alter the content — you are a plain file writer for this task. Content between the markers:\n<<<DOC\n${content}\nDOC>>>`,
    { agentType: 'n8n-autopilot:n8n-author', schema: DOCWRITE_SCHEMA, phase: phaseName }
  )
}

// Build ONE sub-workflow greenfield. Returns build.workflow.js result (status/workflowId/...).
async function buildSub(sub, plan, idMap) {
  const c = contractsFor(sub.slug, plan.handovers)
  const childRefs = (sub.dependsOn || []).map((d) => `${d}=${idMap[d] || 'MISSING'}`).join(', ')
  const desc = [
    sub.purpose,
    `\nINPUT contract: ${c.input}`,
    `OUTPUT contract: ${c.output}`,
    sub.dependsOn && sub.dependsOn.length ? `\nThis is an orchestrator. Sub-workflows you call via an Execute Workflow node (reference by these real workflowIds): ${childRefs}.` : '',
    `\nTrigger: ${sub.trigger}. Name the workflow EXACTLY: "${sub.name}". It is sub-workflow '${sub.slug}' of stack '${plan.stackSlug}'.`,
  ].join('\n')
  return workflow({ scriptPath: buildScript }, { description: desc, testData: '' })
}

// ===================================================================
// GREENFIELD
// ===================================================================
if (!isExtend) {
  // ---- PLAN ----
  phase('Plan')
  const plan = await agent(
    `Decompose this end-to-end use case into a stack of sub-workflows. Follow your DECOMPOSE rules; fix every handover contract; set dependsOn so the graph is acyclic and buildable bottom-up.\nUse case (PRP):\n"""${description}"""`,
    { agentType: 'n8n-autopilot:n8n-stack-architect', schema: STACKPLAN_SCHEMA, model: 'opus', phase: 'Plan' }
  )
  const slugs = plan.subWorkflows.map((s) => s.slug)
  const order = topoSort(slugs, (slug) => (plan.subWorkflows.find((s) => s.slug === slug)?.dependsOn) || [])
  if (!order) return { status: 'failed', stage: 'plan', reason: 'dependency cycle in stackPlan', stackPlan: plan }
  log(`Stack "${plan.stackSlug}": ${slugs.length} sub-WF(s), entry=${plan.entry}. Build order: ${order.join(' → ')}`)

  // ---- DOCUMENT (pre-build, ids pending) ----
  phase('Document')
  const idMap = {}
  const docPath = `docs/${plan.stackSlug}.architecture.md`
  await writeDoc(renderArchitectureDoc(plan, idMap), docPath, 'Document')
  log(`Architecture doc → ${docPath}`)

  // ---- BUILD bottom-up ----
  phase('Build')
  const results = []
  for (const slug of order) {
    const sub = plan.subWorkflows.find((s) => s.slug === slug)
    // A dependency that failed leaves a hole — never build on a broken foundation.
    const brokenDep = (sub.dependsOn || []).find((d) => !idMap[d])
    if (brokenDep) {
      log(`HALT: ${slug} depends on ${brokenDep} which was not built. Stopping.`)
      results.push({ slug, status: 'skipped', reason: `dependency ${brokenDep} not built` })
      break
    }
    log(`Building ${slug} (${sub.kind})…`)
    const r = await buildSub(sub, plan, idMap)
    results.push({ slug, status: r?.status, workflowId: r?.workflowId, url: r?.url, filePath: r?.filePath, attention: r?.attention })
    if (!r || r.status !== 'success' || !r.workflowId) {
      log(`HALT: sub-WF ${slug} did not build green (status=${r?.status}). Dependents will not be built.`)
      break
    }
    idMap[slug] = r.workflowId
    log(`Built ${slug} → ${r.workflowId}`)
  }

  // ---- DOCUMENT (final, real ids) + REPORT ----
  phase('Report')
  await writeDoc(renderArchitectureDoc(plan, idMap), docPath, 'Report')
  const built = results.filter((r) => r.status === 'success').length
  const complete = built === slugs.length
  return {
    status: complete ? 'success' : 'partial',
    mode: 'greenfield', stackSlug: plan.stackSlug, entry: plan.entry,
    architectureDoc: docPath, buildOrder: order,
    subWorkflows: results, builtCount: built, totalCount: slugs.length,
    idMap,
    attention: complete ? '' : `Stack incomplete: ${built}/${slugs.length} sub-WFs built green. First failure halted the rest — see subWorkflows[].`,
  }
}

// ===================================================================
// EXTEND
// ===================================================================
// ---- MIRROR (local call-graph must be complete) ----
phase('Mirror')
let mirror = null
if (syncScript) {
  mirror = await workflow({ scriptPath: syncScript }, {})
  log(`mirror-sync: status=${mirror?.status} pulled=${mirror?.pulled ?? '?'} mirrorComplete=${mirror?.mirrorComplete}`)
} else {
  log('No syncScript passed — skipping mirror-sync. Comprehension may be incomplete if the mirror is stale.')
}

// ---- COMPREHEND ----
phase('Comprehend')
const cur = await agent(
  `Reconstruct the existing stack's call-graph from the local mirror's executeWorkflow references.${target ? ` Target stack (id or name hint): "${target}".` : ''} Requested change (for scoping): """${change}""". Keep only the connected component(s) reachable from the relevant entry trigger.`,
  { agentType: 'n8n-autopilot:n8n-stack-comprehender', schema: CURRENTSTACK_SCHEMA, phase: 'Comprehend' }
)
if (cur.missingLocal && cur.missingLocal.length) log(`WARNING mirror gap: ${cur.missingLocal.length} referenced workflowId(s) have no local file: ${cur.missingLocal.join(', ')}. Re-run mirror-sync.`)
if (cur.docDrift) log(`Doc drift vs reality: ${cur.docDrift}`)
log(`Current stack "${cur.stackSlug}": ${cur.subWorkflows.length} sub-WF(s), ${cur.edges.length} edge(s), entry=${cur.entry}`)

// ---- DELTA-PLAN ----
phase('Plan')
const curBlock = `currentStack:\n  entry: ${cur.entry}\n  subWorkflows: ${cur.subWorkflows.map((s) => `${s.slug}(${s.workflowId},${s.kind})`).join(', ')}\n  edges: ${cur.edges.map((e) => `${e.from}->${e.to}`).join(', ')}`
const delta = await agent(
  `Plan the DELTA for this change against the existing stack.\nChange:\n"""${change}"""\n${curBlock}\nClassify each sub-WF new/changed/unchanged; new ones get full sub-WF specs (slug/name/trigger/kind/purpose/dependsOn); changed ones get {slug, workflowId, changeDescription}; name any handover changes (both producer + consumer).`,
  { agentType: 'n8n-autopilot:n8n-stack-architect', schema: DELTA_SCHEMA, model: 'opus', phase: 'Plan' }
)
log(`Delta: ${delta.newSubWorkflows.length} new, ${delta.changedSubWorkflows.length} changed, ${delta.handoverChanges.length} handover change(s)`)

// idMap seeded with EXISTING sub-WF ids so new orchestrators can reference existing children.
const idMap = {}
for (const s of cur.subWorkflows) idMap[s.slug] = s.workflowId

// A synthetic "plan" so contractsFor / buildSub work for the new sub-WFs.
const handovers = delta.handoverChanges.map((h) => ({ from: h.from, to: h.to, inputContract: h.newInputContract || '(unchanged)', outputContract: h.newOutputContract || '(unchanged)' }))
const synthPlan = { stackSlug: cur.stackSlug, handovers }

// ---- APPLY: new sub-WFs first (bottom-up), then changed ----
phase('Build')
const results = []
const newSlugs = delta.newSubWorkflows.map((s) => s.slug)
const newOrder = topoSort(newSlugs, (slug) => ((delta.newSubWorkflows.find((s) => s.slug === slug)?.dependsOn) || []).filter((d) => newSlugs.includes(d)))
if (newSlugs.length && !newOrder) return { status: 'failed', stage: 'delta', reason: 'dependency cycle among new sub-workflows', delta }

for (const slug of (newOrder || [])) {
  const sub = delta.newSubWorkflows.find((s) => s.slug === slug)
  const brokenDep = (sub.dependsOn || []).find((d) => !idMap[d])
  if (brokenDep) { log(`HALT: new ${slug} depends on ${brokenDep} (not available). Stopping.`); results.push({ slug, status: 'skipped', reason: `dependency ${brokenDep} unavailable` }); break }
  log(`Building NEW ${slug} (${sub.kind})…`)
  const r = await buildSub(sub, synthPlan, idMap)
  results.push({ slug, kind: 'new', status: r?.status, workflowId: r?.workflowId, url: r?.url, filePath: r?.filePath, attention: r?.attention })
  if (!r || r.status !== 'success' || !r.workflowId) { log(`HALT: new sub-WF ${slug} not green (status=${r?.status}).`); break }
  idMap[slug] = r.workflowId
  log(`Built NEW ${slug} → ${r.workflowId}`)
}

// Changed sub-WFs (incl. orchestrators rewiring Execute-Workflow nodes to new/changed child ids).
// Proceed to changed sub-WFs only if every new build (if any) went green. A null/failed build
// pushed a non-'success' status and broke the loop above — that must block rewiring.
const newBuiltOk = results.every((r) => r.status === 'success')
if (newBuiltOk) {
  for (const ch of delta.changedSubWorkflows) {
    const childHint = cur.edges.filter((e) => e.from === ch.slug).map((e) => `${e.to}=${idMap[e.to] || '?'}`).join(', ')
    const changeText = `${ch.changeDescription}${childHint ? `\nIf this rewires Execute-Workflow nodes, the child workflowIds are: ${childHint}.` : ''}`
    log(`Editing CHANGED ${ch.slug} (${ch.workflowId})…`)
    const r = await workflow({ scriptPath: editScript }, { target: ch.workflowId, change: changeText, testData: '' })
    results.push({ slug: ch.slug, kind: 'changed', status: r?.status, workflowId: ch.workflowId, filePath: r?.filePath })
    if (!r || r.status !== 'success') { log(`HALT: edit of ${ch.slug} not green (status=${r?.status}).`); break }
    log(`Edited CHANGED ${ch.slug}`)
  }
} else {
  log('Skipping changed sub-WFs because a new sub-WF failed to build (no rewiring onto a broken child).')
}

// ---- DOCUMENT + REPORT ----
phase('Report')
// Reproject the updated stack into the architecture-doc shape (existing + new, with real ids).
const allSubs = [
  ...cur.subWorkflows.map((s) => ({ slug: s.slug, name: s.name, trigger: s.trigger, kind: s.kind, dependsOn: cur.edges.filter((e) => e.from === s.slug).map((e) => e.to) })),
  ...delta.newSubWorkflows.map((s) => ({ slug: s.slug, name: s.name, trigger: s.trigger, kind: s.kind, dependsOn: s.dependsOn || [] })),
]
const reportPlan = { stackSlug: cur.stackSlug, overview: `Extended via build-stack-v2. Change: ${change}`, entry: cur.entry, subWorkflows: allSubs, handovers }
const docPath = `docs/${cur.stackSlug}.architecture.md`
await writeDoc(renderArchitectureDoc(reportPlan, idMap), docPath, 'Report')

const applied = results.filter((r) => r.status === 'success').length
const planned = (newOrder?.length || 0) + delta.changedSubWorkflows.length
return {
  status: applied === planned ? 'success' : 'partial',
  mode: 'extend', stackSlug: cur.stackSlug, entry: cur.entry,
  architectureDoc: docPath, mirror: mirror ? { status: mirror.status, mirrorComplete: mirror.mirrorComplete } : null,
  missingLocal: cur.missingLocal || [], docDrift: cur.docDrift || null,
  applied: results, appliedCount: applied, plannedCount: planned, idMap,
  attention: applied === planned ? '' : `Extend incomplete: ${applied}/${planned} sub-WFs applied green. First failure halted the rest — see applied[].`,
}
