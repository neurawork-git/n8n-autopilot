#!/bin/bash
# check-schema-versions.sh
# Compares packageVersion in cached community node schemas against latest npm versions.
# Prints STALE/OK/MISSING lines and exits 1 if any schema is stale.
#
# Usage:
#   bash scripts/check-schema-versions.sh          # full check
#   bash scripts/check-schema-versions.sh --quiet  # only print stale entries
#
# Called by: hooks/hooks.json SessionStart, /n8n-autopilot:pull-schemas --check

QUIET=0
[[ "$1" == "--quiet" ]] && QUIET=1

# Consumer-repo path: the user's CWD when the SessionStart hook fires.
# CLAUDE_PLUGIN_ROOT points at the plugin install dir — schemas live in the
# consumer's workspace, not the plugin cache. Bug fixed in 4.2.1.
REPO_DIR="$PWD"
INDEX="$REPO_DIR/schemas/_index.json"

if [ ! -f "$INDEX" ]; then
  [ "$QUIET" -eq 0 ] && echo "⚠️  schemas/_index.json not found — run /n8n-autopilot:pull-schemas"
  exit 0
fi

STALE_COUNT=0
MISSING_COUNT=0

# Extract entries with packageName (Stage 3 schemas) or packageVersion (any versioned schema)
ENTRIES=$(node -e "
const idx = require('$INDEX');
const dir = '$REPO_DIR/schemas/nodes';
const path = require('path');
const fs = require('fs');
const out = [];
for (const [type, meta] of Object.entries(idx)) {
  if (!meta.file) continue;
  const filePath = path.join(dir, meta.file);
  if (!fs.existsSync(filePath)) continue;
  const schema = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  if (schema.packageName && schema.packageVersion) {
    out.push(schema.packageName + '|' + schema.packageVersion + '|' + type);
  }
}
// deduplicate by package name (one check per package, not per node type)
const seen = new Set();
for (const line of out) {
  const pkg = line.split('|')[0];
  if (!seen.has(pkg)) { seen.add(pkg); console.log(line); }
}
" 2>/dev/null)

if [ -z "$ENTRIES" ]; then
  [ "$QUIET" -eq 0 ] && echo "ℹ️  No versioned community schemas found (all from n8nac index). Run pull-schemas to refresh."
  exit 0
fi

[ "$QUIET" -eq 0 ] && echo "=== Community Schema Version Check ==="

STALE_PKGS=""
while IFS='|' read -r pkg cached type; do
  latest=$(npm show "$pkg" version 2>/dev/null)
  if [ -z "$latest" ]; then
    [ "$QUIET" -eq 0 ] && echo "  ❓ UNKNOWN  $pkg (npm unreachable or package not found)"
    continue
  fi
  if [ "$cached" = "$latest" ]; then
    [ "$QUIET" -eq 0 ] && echo "  ✅ OK       $pkg @ $cached"
  else
    echo "  ⚠️  STALE    $pkg  cached=$cached  latest=$latest"
    STALE_COUNT=$((STALE_COUNT + 1))
    STALE_PKGS="${STALE_PKGS:+$STALE_PKGS,}$pkg"
  fi
done <<< "$ENTRIES"

if [ "$STALE_COUNT" -gt 0 ]; then
  echo ""
  echo "$STALE_COUNT stale schema(s) found. Run: /n8n-autopilot:pull-schemas --community-only"
  # Machine-parsable signal for Claude to auto-trigger the action (see CLAUDE.md Auto-Reactions).
  if [ -n "$STALE_PKGS" ]; then
    echo "AUTOPILOT_ACTION_REQUIRED: /n8n-autopilot:pull-schemas --community-only --packages $STALE_PKGS"
  else
    echo "AUTOPILOT_ACTION_REQUIRED: /n8n-autopilot:pull-schemas --community-only"
  fi
fi

[ "$QUIET" -eq 0 ] && [ "$STALE_COUNT" -eq 0 ] && echo "All community schemas are up-to-date."

# Note: Installed-node-coverage check is owned by setup-check.sh (Section 7).
# Don't call it here too — would double-fire per SessionStart.

if [ "$STALE_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
