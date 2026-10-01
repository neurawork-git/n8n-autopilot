#!/usr/bin/env bash
# Build the local, structured cache of everything n8nac can tell us about the ACTIVE instance,
# and write it to .n8n-autopilot/instance-cache.json.
#
# Why this exists: before this, nothing on disk described the instance. `schemas/` holds node
# definitions from n8nac's own knowledge base (instance-independent), `docs/INVENTORY.md` is prose
# for humans, and `.n8n-state.json` holds only a sync hash. So every build agent researched the
# public 7.7k-template corpus and never looked at the workflows already running next door.
#
# The cache answers three questions the agents actually need:
#   1. What already runs here?          -> workflows[] (+ file, trigger, node types, credentials)
#   2. Which node types are proven here? -> nodeTypeUsage{} (a type with count>0 demonstrably works)
#   3. What can I wire up?               -> credentials[], customNodes[]
#
# Reads only. n8nac CLI only — never the REST API (blocked by the PreToolUse guard, and rightly so).
#
# Usage:  bash scripts/build-instance-cache.sh [--quiet]
# Env:    N8NAC_ENVIRONMENT must be set (the env-gate enforces this for every instance command).

set -uo pipefail

QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1
say() { [ "$QUIET" -eq 0 ] && echo "$@"; return 0; }

REPO_DIR="$PWD"
OUT_DIR="$REPO_DIR/.n8n-autopilot"
OUT="$OUT_DIR/instance-cache.json"

if [ -z "${N8NAC_ENVIRONMENT:-}" ]; then
  echo "ERROR: N8NAC_ENVIRONMENT is not set. Export it (never \`env use\`) and re-run." >&2
  exit 1
fi

say "=== Building instance cache (env=$N8NAC_ENVIRONMENT) ==="

ENV_JSON=$(npx --yes n8nac env status --json 2>/dev/null)
if [ -z "$ENV_JSON" ]; then
  echo "ERROR: \`n8nac env status --json\` returned nothing — instance unreachable or env unknown." >&2
  exit 1
fi

# `list` reaches the instance; empty output means unreachable, which must NOT be cached as
# "this instance has no workflows" — a caller would read that as a green light to build from scratch.
LIST_JSON=$(npx --yes n8nac list --json 2>/dev/null)
if [ -z "$LIST_JSON" ]; then
  echo "ERROR: \`n8nac list --json\` returned nothing — instance unreachable. Cache NOT written." >&2
  exit 1
fi

CRED_JSON=$(npx --yes n8nac credential list --json 2>/dev/null || echo '[]')

mkdir -p "$OUT_DIR"

ENV_JSON="$ENV_JSON" LIST_JSON="$LIST_JSON" CRED_JSON="$CRED_JSON" OUT="$OUT" REPO_DIR="$REPO_DIR" \
node -e '
const fs = require("fs"), path = require("path");
const parse = (s, fb) => { try { return JSON.parse(s) } catch (e) { return fb } };
const arr = (v) => Array.isArray(v) ? v : (v && Array.isArray(v.workflows) ? v.workflows : (v && Array.isArray(v.credentials) ? v.credentials : []));

const envJson  = parse(process.env.ENV_JSON, {});
const workflows = arr(parse(process.env.LIST_JSON, []));
const creds     = arr(parse(process.env.CRED_JSON, []));
const repoDir  = process.env.REPO_DIR;

const wfPath = (envJson.environment && envJson.environment.workflowsPath) || path.join(repoDir, "workflows");

// A node type is anything n8n would resolve as one: core, community package, or scoped @n8n/*.
const TYPE_RE = /type:\s*[\x27"]((?:n8n-nodes-|@n8n\/)[^\x27"]+)[\x27"]/g;
const TRIGGER_RE = /(trigger|webhook)/i;

const readNodeTypes = (file) => {
  try {
    const src = fs.readFileSync(file, "utf8");
    const out = new Set();
    let m;
    while ((m = TYPE_RE.exec(src)) !== null) out.add(m[1]);
    // credentials are authored inline as { id, name } — collect the names for wiring hints
    const credNames = new Set();
    const cre = /credentials:\s*{[^}]*name:\s*[\x27"]([^\x27"]+)[\x27"]/g;
    let c; while ((c = cre.exec(src)) !== null) credNames.add(c[1]);
    return { types: [...out], credentialNames: [...credNames] };
  } catch (e) { return null }
};

const usage = {};
const entries = workflows.map((w) => {
  const file = w.filename ? path.join(wfPath, w.filename) : null;
  const local = file && fs.existsSync(file) ? readNodeTypes(file) : null;
  const types = local ? local.types : [];
  for (const t of types) usage[t] = (usage[t] || 0) + 1;
  return {
    id: w.id,
    name: w.name,
    active: !!w.active,
    archived: !!w.isArchived,
    syncStatus: w.status || null,
    folder: w.folderPathString || "",
    file: local ? file : null,          // null = remote-only or mirror gap: not readable as a reference
    trigger: types.find((t) => TRIGGER_RE.test(t)) || null,
    nodeTypes: types,
    credentialNames: local ? local.credentialNames : [],
  };
});

// A type used by an ACTIVE workflow is proven twice over: it exists on this instance AND it runs.
const provenActive = {};
for (const e of entries) if (e.active) for (const t of e.nodeTypes) provenActive[t] = (provenActive[t] || 0) + 1;

let customNodes = [];
const sidecar = path.join(repoDir, "n8nac-custom-nodes.json");
if (fs.existsSync(sidecar)) {
  const sc = parse(fs.readFileSync(sidecar, "utf8"), {});
  customNodes = Object.values(sc.nodes || {}).map((n) => ({ type: n.type, displayName: n.displayName, version: n.version }));
}

const cache = {
  generatedAt: new Date().toISOString(),
  environment: {
    name: envJson.environmentName || null,
    project: (envJson.environment && envJson.environment.projectName) || null,
    host: (envJson.instance && envJson.instance.url) || null,
    workflowsPath: wfPath,
  },
  // n8nac 2.5.0 exposes NO n8n version and no remote node JSON (`pull` drops typeVersion on
  // conversion, `.n8n-state.json` keeps only a hash). So typeVersion ceilings cannot be derived
  // locally today — recorded here as a known gap rather than guessed.
  n8nVersion: null,
  n8nVersionSource: "unavailable: n8nac exposes no instance version (env status has no version field)",
  counts: {
    workflows: entries.length,
    active: entries.filter((e) => e.active).length,
    mirroredLocally: entries.filter((e) => e.file).length,
    credentials: creds.length,
    customNodes: customNodes.length,
  },
  workflows: entries,
  nodeTypeUsage: usage,
  nodeTypesProvenOnActiveWorkflows: provenActive,
  credentials: creds.map((c) => ({ id: c.id, name: c.name, type: c.type })),
  customNodes,
};

fs.writeFileSync(process.env.OUT, JSON.stringify(cache, null, 2) + "\n");

// The JSON is ~80 KB at 78 workflows — too big to drop into every agent context. The brief is the
// part an agent reads whole; the JSON is what it greps when it needs one workflow`s detail.
const top = Object.entries(provenActive).sort((a, b) => b[1] - a[1]);
const actives = entries.filter((e) => e.active);
const brief = [
  `# Instance brief — ${cache.environment.name} (${cache.environment.project})`,
  ``,
  `Host: ${cache.environment.host} · generated ${cache.generatedAt}`,
  `Full detail: \`.n8n-autopilot/instance-cache.json\` (grep it, do not read it whole).`,
  ``,
  `${cache.counts.workflows} workflows, ${cache.counts.active} active, ${cache.counts.credentials} credentials, ${cache.counts.customNodes} custom nodes.`,
  ``,
  `## Node types proven on ACTIVE workflows`,
  ``,
  `These types demonstrably exist on this instance and run. Prefer them over anything you read in a`,
  `public template. A type absent from this list is not forbidden — it is unproven HERE.`,
  ``,
  ...top.slice(0, 40).map(([t, n]) => `- \`${t}\` — ${n}`),
  top.length > 40 ? `- …${top.length - 40} more in the JSON (\`nodeTypesProvenOnActiveWorkflows\`)` : ``,
  ``,
  `## Active workflows (candidate references)`,
  ``,
  `Read one of these files before authoring something similar — a working local twin beats a`,
  `public template that was never run against this instance.`,
  ``,
  ...actives.slice(0, 40).map((e) => `- \`${e.id}\` **${e.name}** — trigger: ${e.trigger || "n/a"} — ${e.nodeTypes.length} nodes${e.file ? "" : " — NOT mirrored locally"}`),
  actives.length > 40 ? `- …${actives.length - 40} more in the JSON (\`workflows[]\`, \`active: true\`)` : ``,
  ``,
  `## Known gap`,
  ``,
  `\`n8nVersion\` is null: ${cache.n8nVersionSource}. There is no local ground truth for which`,
  `\`typeVersion\` this instance accepts — n8nac compiles the highest version it knows. Treat a node`,
  `that fails on push/activate with a version complaint as this gap, not as an authoring error.`,
  ``,
].join("\n");
fs.writeFileSync(process.env.OUT.replace(/instance-cache\.json$/, "instance-brief.md"), brief);
console.log(`  workflows: ${cache.counts.workflows} (${cache.counts.active} active, ${cache.counts.mirroredLocally} readable locally)`);
console.log(`  distinct node types in use: ${Object.keys(usage).length}`);
console.log(`  credentials: ${cache.counts.credentials} | custom nodes: ${cache.counts.customNodes}`);
' || { echo "ERROR: cache assembly failed — cache NOT written." >&2; exit 1; }

say "  -> $OUT"
