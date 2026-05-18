---
name: pull-schemas
description: Pull/update node schemas for offline validation. Uses n8nac MCP for core nodes, npm registry for community nodes. Run when schemas are stale or new nodes are needed.
argument-hint: "[--core-only] [--community-only] [--nodes node1,node2] [--packages pkg1,pkg2]"
user-invocable: true
allowed-tools: Read, Edit, Write, Grep, Glob, Bash(npx:*), Bash(node:*), Bash(npm:*), Bash(mkdir:*), Bash(cat:*), Bash(bash:*), mcp__n8n-as-code__*
---

> **Flags:**
> - `--core-only` — skip community nodes entirely
> - `--community-only` — skip core nodes entirely
> - `--nodes <list>` — restrict to specific n8n node type identifiers (e.g. `n8n-nodes-base.httpRequest`)
> - `--packages <list>` — restrict to specific npm package names (e.g. `n8n-nodes-firecrawl,n8n-nodes-mcp`) — used by SessionStart auto-reactions to refresh only the stale packages reported by `check-schema-versions.sh` / `check-installed-nodes.sh`. When this flag is set, jump directly to Stage 3 (npm registry extraction) for each listed package.

# Pull Node Schemas

Fetch node schemas and cache them locally in `schemas/nodes/`.

**Three-stage approach:**
1. **Core nodes** → `get_n8n_node_info` (n8nac MCP) — 537+ nodes, offline
2. **Community nodes (indexed)** → `npx n8nac skills node-info <node_type>` — 547 community nodes
3. **Community nodes (not indexed)** → npm registry + node instantiation — for nodes unknown to n8nac

> **Key learning:** n8nac only indexes a subset of community nodes. Many niche packages are not findable via MCP search. The npm registry approach (Stage 3) works for any published npm package regardless of indexing.

Schemas are stored in `schemas/nodes/{node_type}.json` and indexed in `schemas/_index.json`.

## Steps

### 1. Stage 1: Core Nodes via n8nac

For each node type, call:

```
mcp__n8n-as-code__get_n8n_node_info(name="{node_type}")
```

Save the response to `schemas/nodes/{node_type}.json`.

**Parallelization:** Call up to 5 nodes in parallel.

### 2. Stage 2: Community Nodes via n8nac

Try for each community node:

```bash
npx n8nac skills node-info <node_type>
```

If "not found" → proceed to Stage 3.

### 3. Stage 3: Community Nodes via npm registry (fallback)

For nodes not found in n8nac, extract schemas directly from the npm package.

```bash
# 1. Install packages + n8n-workflow peer dep in a temp dir
mkdir -p /tmp/n8n_schema_runner
cat > /tmp/n8n_schema_runner/package.json << 'EOF'
{"name":"schema-runner","version":"1.0.0","dependencies":{
  "<package-name>": "*",
  "n8n-workflow": "*"
}}
EOF
cd /tmp/n8n_schema_runner && npm install --silent

# 2. Extract description from each node file listed in package.json n8n.nodes[]
node -e "
const fs = require('fs');
const path = require('path');
const outDir = '<repo>/schemas/nodes';
const pkg = '<package-name>';
const pkgJson = JSON.parse(fs.readFileSync('node_modules/' + pkg + '/package.json', 'utf8'));
for (const relPath of pkgJson.n8n?.nodes || []) {
  const mod = require(path.resolve('node_modules/' + pkg, relPath));
  for (const [, cls] of Object.entries(mod)) {
    if (typeof cls !== 'function') continue;
    let inst; try { inst = new cls(); } catch(e) { continue; }
    const desc = inst.description;
    if (!desc?.name || !desc?.properties) continue;

    // CRITICAL: Derive the full n8n type key.
    // Scoped packages (@scope/pkg): type = '@scope/pkg.desc.name'  (e.g. '@mendable/n8n-nodes-firecrawl.firecrawl')
    // Unscoped packages (n8n-nodes-foo): type = desc.name           (e.g. 'closeCrm')
    const nodeType = pkg.startsWith('@') ? pkg + '.' + desc.name : desc.name;

    // Determine output path: scoped packages get their own subdirectory
    const scope = pkg.startsWith('@') ? pkg.split('/')[0] : null;
    const subDir = scope ? path.join(outDir, scope) : outDir;
    fs.mkdirSync(subDir, { recursive: true });
    // File name: '<full-package-name>.<desc.name>.json' for scoped, '<desc.name>.json' for unscoped
    const filename = scope
      ? pkg.split('/')[1] + '.' + desc.name + '.json'
      : desc.name + '.json';

    const schema = {
      type: nodeType,
      packageName: pkg,
      packageVersion: pkgJson.version,
      displayName: desc.displayName, description: desc.description,
      version: desc.version, defaults: desc.defaults,
      credentials: desc.credentials || [], properties: desc.properties || []
    };
    fs.writeFileSync(path.join(subDir, filename), JSON.stringify(schema, null, 2));
    console.log('✅', nodeType, '(' + desc.properties.length + ' props)');
  }
}
"
```

**Why this works:** Every n8n community node exports a class with a `description` property containing the full parameter schema. The npm tarball always contains this compiled JS, so we can instantiate it locally.

**Type key rule:** n8nac validation looks up the exact node type string used in Decorator-TS (e.g. `type: '@mendable/n8n-nodes-firecrawl.firecrawl'`). Using only `desc.name` for scoped packages creates a broken index entry that validation can never find.

**Requirement:** `n8n-workflow` must be available as a peer dependency (always present in this repo's `node_modules`). For the temp runner, install it explicitly.

### 4. Rebuild Index

After all schemas are cached, rebuild `schemas/_index.json`:

```bash
node -e "
const fs = require('fs');
const path = require('path');
const dir = 'schemas/nodes';

function getFiles(d, base) {
  const result = [];
  for (const f of fs.readdirSync(d, {withFileTypes: true})) {
    if (f.isDirectory()) result.push(...getFiles(path.join(d, f.name), (base||'') + f.name + '/'));
    else if (f.name.endsWith('.json') && f.name !== '.gitkeep') result.push((base||'') + f.name);
  }
  return result;
}

const files = getFiles(dir);
const index = {};
for (const f of files) {
  const data = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
  const type = data.type || f.replace('.json', '');
  index[type] = { file: f, displayName: data.displayName || type, packageVersion: data.packageVersion || null };
}
fs.writeFileSync('schemas/_index.json', JSON.stringify(index, null, 2));
console.log('Index rebuilt:', Object.keys(index).length, 'schemas');
"
```

### 5. Update COMMUNITY_NODES.md

Set schema column to `✅ cached` for newly added nodes.

### 6. Verify

```bash
npm test
```

### 7. Staleness + Coverage Check (Optional — run before Stage 3)

Before pulling, run the combined check:

```bash
bash scripts/check-schema-versions.sh
```

This does two things:
1. **Staleness:** Compares `packageVersion` in cached schemas against the latest npm version. Any `STALE` entries should be refreshed via Stage 3.
2. **Coverage:** Queries the live n8n instance (`/api/v1/community-packages`) and reports any installed node whose type is not in `schemas/_index.json`.

Requires `.env` with `N8N_API_URL` and `N8N_API_KEY` for the coverage check. Runs non-blocking — skips gracefully if unavailable.

The coverage check (`check-installed-nodes.sh`) can also be run standalone:

```bash
bash scripts/check-installed-nodes.sh
```

## When to Auto-Trigger This Skill

This skill must run **automatically** (not just on manual request) in these situations:

| Situation | What to do |
|-----------|-----------|
| `get_n8n_node_info` returns empty/not-found for a community node | Run Stage 3 for that specific npm package immediately |
| n8nac validation reports `unknown node type` warning | Run Stage 3 for the affected package, rebuild index, re-validate |
| `packageVersion: null` in `_index.json` for a community node | Run Stage 3 to get a versioned schema from npm |
| SessionStart reports `STALE` schemas | Run Stage 3 for all stale packages |

**In `build-workflow`:** If Phase 0 `get_n8n_node_info` returns no result for a community node, run Stage 3 inline before proceeding to Phase 1. The gate "verified parameter names for every node" requires a valid schema.

## Notes

- Schemas are committed to git — they persist across sessions and are bundled with the plugin
- Existing schemas are overwritten (intentional — we want fresh data)
- `packageVersion` field in schema JSON tracks which npm version was used — check for drift when updating
- `packageName` field (Stage 3 only) stores the full npm package name for staleness checks
