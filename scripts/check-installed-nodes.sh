#!/bin/bash
# check-installed-nodes.sh
# Fetches installed community packages from the live n8n instance and checks
# whether their node schemas are present in schemas/_index.json.
# Reports nodes that are installed but have no cached schema.
#
# Usage:
#   bash scripts/check-installed-nodes.sh          # full output
#   bash scripts/check-installed-nodes.sh --quiet  # only print missing entries
#
# Called by: scripts/check-schema-versions.sh (appended to SessionStart output)
# Requires: .env with N8N_API_URL and N8N_API_KEY

QUIET=0
[[ "$1" == "--quiet" ]] && QUIET=1

REPO_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
INDEX="$REPO_DIR/schemas/_index.json"
ENV_FILE="$REPO_DIR/.env"

# ── 1. Load N8N_API_URL and N8N_API_KEY from .env ────────────────────────────
if [ ! -f "$ENV_FILE" ]; then
  [ "$QUIET" -eq 0 ] && echo "  ℹ️  check-installed-nodes: .env not found — skipping."
  exit 0
fi

# Source only N8N_API_URL and N8N_API_KEY lines (ignore comments, handle quotes)
eval "$(grep -E '^N8N_API_(URL|KEY)=' "$ENV_FILE" | head -2)"

if [ -z "$N8N_API_URL" ] || [ -z "$N8N_API_KEY" ]; then
  [ "$QUIET" -eq 0 ] && echo "  ℹ️  check-installed-nodes: N8N_API_URL or N8N_API_KEY not set in .env — skipping."
  exit 0
fi

N8N_HOST="${N8N_API_URL%/}"

# ── 2. Fetch installed community packages from n8n API ───────────────────────
PACKAGES_JSON=$(curl -s --max-time 10 \
  -H "X-N8N-API-KEY: $N8N_API_KEY" \
  -H "Accept: application/json" \
  "${N8N_HOST}/api/v1/community-packages" 2>/dev/null)

if [ -z "$PACKAGES_JSON" ]; then
  [ "$QUIET" -eq 0 ] && echo "  ℹ️  check-installed-nodes: Could not reach ${N8N_HOST}/api/v1/community-packages — skipping."
  exit 0
fi

# ── 3. Compare installed node types against _index.json ──────────────────────
if [ ! -f "$INDEX" ]; then
  [ "$QUIET" -eq 0 ] && echo "  ℹ️  check-installed-nodes: schemas/_index.json not found — run /n8n-autopilot:pull-schemas first."
  exit 0
fi

TMPFILE=$(mktemp /tmp/n8n_installed_XXXXXX.json)
printf '%s' "$PACKAGES_JSON" > "$TMPFILE"

node -e "
const fs = require('fs');
const quiet = process.argv[3] === '1';

let packages;
try {
  packages = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
} catch(e) {
  // Cannot parse response — silently skip
  process.exit(0);
}

// n8n API may return an array or { data: [...] }
const list = Array.isArray(packages) ? packages : (packages.data || packages.items || []);

if (list.length === 0) {
  if (!quiet) console.log('  ℹ️  No community packages installed on this instance.');
  process.exit(0);
}

const index = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const knownTypes = new Set(Object.keys(index));

const missing = [];
let total = 0;

for (const pkg of list) {
  const pkgName = pkg.packageName || pkg.name || '';
  for (const node of (pkg.installedNodes || [])) {
    const nodeType = node.name || node.type || '';
    if (!nodeType) continue;
    total++;
    if (!knownTypes.has(nodeType)) {
      missing.push({ pkg: pkgName, type: nodeType });
    }
  }
}

if (missing.length === 0) {
  if (!quiet) console.log('  ✅ All ' + total + ' installed community node(s) have cached schemas.');
  process.exit(0);
}

for (const m of missing) {
  console.log('  ⚠️  NO SCHEMA  ' + m.type + '  (package: ' + m.pkg + ')');
}
console.log('');
console.log('  ' + missing.length + ' of ' + total + ' installed node(s) have no cached schema.');
console.log('  → Run: /n8n-autopilot:pull-schemas');
console.log('    Or add the package to docs/COMMUNITY_NODES.md first.');
// Machine-parsable signal for Claude to auto-trigger the action (see CLAUDE.md Auto-Reactions).
const missingPkgs = Array.from(new Set(missing.map(m => m.pkg).filter(Boolean))).join(',');
if (missingPkgs) {
  console.log('AUTOPILOT_ACTION_REQUIRED: /n8n-autopilot:pull-schemas --community-only --packages ' + missingPkgs);
} else {
  console.log('AUTOPILOT_ACTION_REQUIRED: /n8n-autopilot:pull-schemas');
}
process.exit(1);
" "$TMPFILE" "$INDEX" "$QUIET" 2>/dev/null

NODERC=$?
rm -f "$TMPFILE"
exit $NODERC
