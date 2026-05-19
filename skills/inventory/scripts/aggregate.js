#!/usr/bin/env node
/**
 * aggregate.js — Walk workflows/**.workflow.ts and aggregate node/credential/LLM/trigger usage.
 *
 * Outputs:
 *   --markdown <path>  Write a human-readable report (default: docs/INVENTORY.md)
 *   --json <path>      Also write machine-readable JSON (default: omit)
 *   --dry-run          Print the report to stdout, do not write files
 *   --workspace <dir>  Workspace root (default: $PWD)
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const argv = process.argv.slice(2);
const opts = { markdown: 'docs/INVENTORY.md', json: null, dryRun: false, workspace: process.cwd() };
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--markdown')      opts.markdown = argv[++i];
  else if (a === '--json')     opts.json = argv[++i];
  else if (a === '--dry-run')  opts.dryRun = true;
  else if (a === '--workspace') opts.workspace = argv[++i];
  else if (a === '-h' || a === '--help') {
    process.stdout.write(`Usage: node aggregate.js [--markdown path] [--json path] [--dry-run] [--workspace dir]\n`);
    process.exit(0);
  } else {
    console.error(`unknown flag: ${a}`);
    process.exit(2);
  }
}

const workspaceRoot = path.resolve(opts.workspace);
const wfDir = path.join(workspaceRoot, 'workflows');

if (!fs.existsSync(wfDir)) {
  console.error(`No workflows/ directory at ${wfDir}`);
  process.exit(1);
}

// ── Find workflow files
function walk(d, acc = []) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p, acc);
    else if (e.isFile() && e.name.endsWith('.workflow.ts')) acc.push(p);
  }
  return acc;
}
const files = walk(wfDir).sort();
if (files.length === 0) {
  console.error(`No *.workflow.ts files found under ${wfDir}`);
  process.exit(1);
}

// ── Regexes (single source of truth)
const NODE_TYPE_RE = /^\s+type:\s*'(@[a-zA-Z][^/]+\/n8n-nodes-[^']+|n8n-nodes-base\.[^']+|n8n-nodes-[^']+)'/gm;
const CRED_RE      = /credentials:\s*\{\s*([a-zA-Z][a-zA-Z0-9]*)\s*:/g;
const LLM_VALUE_RE = /value:\s*'((?:gpt|claude|llama|gemini|mistral|o[0-9])[^']+)'/g;
const TRIGGER_HINT = /Trigger$|^webhook$|^schedule$|^chatTrigger$|^formTrigger$|^mcpTrigger$|^manualTrigger$|^errorTrigger$/;
const WORKFLOW_NAME_RE = /@workflow\(\s*\{[^}]*name:\s*['"]([^'"]+)['"]/;

const nodeCounts = {};       // type → count
const credCounts = {};       // credType → count
const credToFiles = {};      // credType → Set<file>
const llmCounts = {};        // model → count
const llmProvider = {        // node-type → provider tag
  '@n8n/n8n-nodes-langchain.lmChatOpenAi':       'OpenAI',
  '@n8n/n8n-nodes-langchain.lmChatAnthropic':    'Anthropic',
  '@n8n/n8n-nodes-langchain.lmChatOllama':       'Ollama',
  '@n8n/n8n-nodes-langchain.lmChatGoogleGemini': 'Google',
  '@n8n/n8n-nodes-langchain.lmChatGoogleVertex': 'Google',
  '@n8n/n8n-nodes-langchain.lmChatMistralCloud': 'Mistral'
};
const llmModelProvider = {}; // model → provider (best guess from concurrent nodes)
const triggerCounts = {};    // trigger type → count
const workflowNames = [];    // [{file, name}]

for (const f of files) {
  const src = fs.readFileSync(f, 'utf8');
  const rel = path.relative(workspaceRoot, f).replace(/\\/g, '/');

  // Workflow name
  const nameMatch = src.match(WORKFLOW_NAME_RE);
  workflowNames.push({ file: rel, name: nameMatch ? nameMatch[1] : path.basename(f, '.workflow.ts') });

  // Node types
  let lastProviderHint = null;
  let m;
  NODE_TYPE_RE.lastIndex = 0;
  while ((m = NODE_TYPE_RE.exec(src)) !== null) {
    const t = m[1];
    nodeCounts[t] = (nodeCounts[t] || 0) + 1;
    // Trigger detection (after stripping the package prefix)
    const short = t.includes('.') ? t.split('.').pop() : t;
    if (TRIGGER_HINT.test(short)) triggerCounts[short] = (triggerCounts[short] || 0) + 1;
    if (llmProvider[t]) lastProviderHint = llmProvider[t];
  }

  // Credentials
  CRED_RE.lastIndex = 0;
  const credsInFile = new Set();
  while ((m = CRED_RE.exec(src)) !== null) {
    const c = m[1];
    if (c === 'credentials') continue; // false-positive guard
    credCounts[c] = (credCounts[c] || 0) + 1;
    credsInFile.add(c);
  }
  for (const c of credsInFile) {
    if (!credToFiles[c]) credToFiles[c] = new Set();
    credToFiles[c].add(rel);
  }

  // LLM model strings
  LLM_VALUE_RE.lastIndex = 0;
  while ((m = LLM_VALUE_RE.exec(src)) !== null) {
    const model = m[1];
    llmCounts[model] = (llmCounts[model] || 0) + 1;
    if (!llmModelProvider[model] && lastProviderHint) llmModelProvider[model] = lastProviderHint;
  }
}

// ── Remote metadata (best-effort)
let remoteSummary = null;
try {
  const out = execSync('npx --yes n8nac list --json --include-archived', {
    cwd: workspaceRoot,
    stdio: ['ignore', 'pipe', 'ignore'],
    maxBuffer: 16 * 1024 * 1024
  }).toString();
  const arr = JSON.parse(out);
  remoteSummary = {
    total:    arr.length,
    active:   arr.filter(w => w.active === true).length,
    archived: arr.filter(w => w.isArchived === true).length
  };
} catch (e) { /* offline / not bound — skip section */ }

// ── Classify nodes
const coreNodes = {};
const communityNodes = {};   // pkg → { node → count }
for (const [type, count] of Object.entries(nodeCounts)) {
  if (type.startsWith('n8n-nodes-base.')) {
    coreNodes[type.replace('n8n-nodes-base.', '')] = count;
  } else {
    const lastDot = type.lastIndexOf('.');
    const pkg = type.slice(0, lastDot);
    const node = type.slice(lastDot + 1);
    if (!communityNodes[pkg]) communityNodes[pkg] = {};
    communityNodes[pkg][node] = count;
  }
}

const sortedDesc = (obj) => Object.entries(obj).sort((a, b) => b[1] - a[1]);

// ── Build markdown
const today = new Date().toISOString().slice(0, 10);
const lines = [];
lines.push(`# n8n Workflow Inventory`);
lines.push('');
lines.push(`> Auto-generated by \`/n8n-autopilot:inventory\` on ${today}. Do not edit by hand.`);
lines.push('');
lines.push(`## Summary`);
lines.push('');
lines.push(`| Metric | Count |`);
lines.push(`|---|---|`);
lines.push(`| Local workflow files | ${files.length} |`);
lines.push(`| Remote workflows (total) | ${remoteSummary ? remoteSummary.total : 'N/A'} |`);
lines.push(`| Active (remote) | ${remoteSummary ? remoteSummary.active : 'N/A'} |`);
lines.push(`| Archived (remote) | ${remoteSummary ? remoteSummary.archived : 'N/A'} |`);
lines.push('');

lines.push(`## Trigger Distribution`);
lines.push('');
const triggers = sortedDesc(triggerCounts);
if (triggers.length === 0) {
  lines.push('_(none detected)_');
} else {
  lines.push(`| Trigger | Count |`);
  lines.push(`|---|---|`);
  for (const [t, c] of triggers) lines.push(`| ${t} | ${c} |`);
}
lines.push('');

lines.push(`## Node Usage — Core (\`n8n-nodes-base\`)`);
lines.push('');
const core = sortedDesc(coreNodes);
if (core.length === 0) {
  lines.push('_(none)_');
} else {
  lines.push(`| Node | Count |`);
  lines.push(`|---|---|`);
  for (const [n, c] of core.slice(0, 30)) lines.push(`| ${n} | ${c} |`);
}
lines.push('');

lines.push(`## Node Usage — Community`);
lines.push('');
const commRows = [];
for (const [pkg, nodes] of Object.entries(communityNodes)) {
  for (const [n, c] of Object.entries(nodes)) commRows.push([pkg, n, c]);
}
commRows.sort((a, b) => b[2] - a[2]);
if (commRows.length === 0) {
  lines.push('_(none)_');
} else {
  lines.push(`| Package | Node | Count |`);
  lines.push(`|---|---|---|`);
  for (const [p, n, c] of commRows) lines.push(`| ${p} | ${n} | ${c} |`);
}
lines.push('');

lines.push(`## LLM Models`);
lines.push('');
const llmRows = sortedDesc(llmCounts);
if (llmRows.length === 0) {
  lines.push('_(none detected)_');
} else {
  lines.push(`| Provider | Model | Count |`);
  lines.push(`|---|---|---|`);
  for (const [m, c] of llmRows) {
    const prov = llmModelProvider[m] || 'Other';
    lines.push(`| ${prov} | ${m} | ${c} |`);
  }
}
lines.push('');

lines.push(`## Credentials`);
lines.push('');
const credRows = sortedDesc(credCounts);
if (credRows.length === 0) {
  lines.push('_(none)_');
} else {
  lines.push(`| Credential Type | Count | Example Workflows (max 3) |`);
  lines.push(`|---|---|---|`);
  for (const [credType, count] of credRows) {
    const examples = Array.from(credToFiles[credType] || []).slice(0, 3).map(p => {
      const wn = workflowNames.find(w => w.file === p);
      return wn ? wn.name : path.basename(p, '.workflow.ts');
    }).join(', ');
    lines.push(`| ${credType} | ${count} | ${examples} |`);
  }
}
lines.push('');

const report = lines.join('\n');

// ── Write outputs
if (opts.dryRun) {
  process.stdout.write(report + '\n');
} else {
  const mdAbs = path.resolve(workspaceRoot, opts.markdown);
  fs.mkdirSync(path.dirname(mdAbs), { recursive: true });
  fs.writeFileSync(mdAbs, report);
  console.log(`wrote ${path.relative(workspaceRoot, mdAbs).replace(/\\/g, '/')}`);
}

if (opts.json) {
  const jsonAbs = path.resolve(workspaceRoot, opts.json);
  fs.mkdirSync(path.dirname(jsonAbs), { recursive: true });
  fs.writeFileSync(jsonAbs, JSON.stringify({
    generatedAt: today,
    summary: { localFiles: files.length, remote: remoteSummary },
    triggers: triggerCounts,
    coreNodes,
    communityNodes,
    llmModels: llmCounts,
    credentials: credCounts
  }, null, 2));
  console.log(`wrote ${path.relative(workspaceRoot, jsonAbs).replace(/\\/g, '/')}`);
}

// ── Console summary
console.error(`Scanned ${files.length} workflow file(s).`);
console.error(`  Core node types : ${Object.keys(coreNodes).length}`);
console.error(`  Community types : ${commRows.length}`);
console.error(`  LLM models      : ${llmRows.length}`);
console.error(`  Credential types: ${credRows.length}`);
