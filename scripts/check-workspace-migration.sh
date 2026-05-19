#!/usr/bin/env bash
# check-workspace-migration.sh
# Detects n8nac workspace state that requires a one-shot migration:
#   1. Legacy in-repo `./n8nac-config.json` (n8nac < 2.2 storage model) → suggests `workspace migrate-v1 --write`
#   2. `workspace status` reports `dry-run` / `migration-required` (v3 → v4 storage finalization) → suggests `workspace migrate --write`
#
# Surfaces an INFO block to the user. Does NOT auto-execute (`migrate --write`
# moves files; user should run consciously). Exits 0 always so it does not
# block SessionStart.
#
# Usage:
#   bash scripts/check-workspace-migration.sh          # full report
#   bash scripts/check-workspace-migration.sh --quiet  # only print when migration needed
#
# Called by: hooks/hooks.json SessionStart (quiet mode)

QUIET=0
[[ "$1" == "--quiet" ]] && QUIET=1

# Consumer-repo path: the user's CWD when the SessionStart hook fires.
# CLAUDE_PLUGIN_ROOT points at the *plugin install* dir, not the workspace —
# do not use it as a substitute for $PWD.
REPO_DIR="$PWD"

# Skip silently if n8nac is unavailable.
if ! command -v npx &>/dev/null; then
  exit 0
fi

LEGACY_FOUND=0
DRY_RUN=0

# ── 1. Workspace-local n8nac-config.json (any format) ──────────────────────
# In n8nac >= 2.2 the workspace config lives in user home (~/n8nac-config.json
# + ~/.n8n-manager/). A copy in the repo means one of:
#   - version 1 / 2 schema: legacy pre-2.2 config (data + location both old)
#   - version 4 schema:     content is current but file is still in workspace
# Either way, `workspace migrate-v1 --write` relocates it correctly.
LEGACY_VERSION=""
if [ -f "$REPO_DIR/n8nac-config.json" ]; then
  LEGACY_FOUND=1
  # Pipe via stdin to avoid Windows-path quoting issues in `require()`.
  LEGACY_VERSION=$(cat "$REPO_DIR/n8nac-config.json" 2>/dev/null | node -e "
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
  try { const j=JSON.parse(d); process.stdout.write(String(j.version||'unknown')); }
  catch(e){ process.stdout.write('parse-error'); }
});" 2>/dev/null || echo "unknown")
fi

# ── 2. workspace status — dry-run / migration-required ──────────────────────
# workspace status returns two distinct shapes:
#   - BOUND:     { version, activeEnvironment: {...}, ... }  → no `status` field
#   - PENDING:   { status: "dry-run" | "migration-required", operations: [...] }
WS_STATUS=""
WS_JSON=$(npx --yes n8nac workspace status --json 2>/dev/null || echo "")
if [ -n "$WS_JSON" ]; then
  WS_STATUS=$(echo "$WS_JSON" | node -e "
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
  try { const j=JSON.parse(d); process.stdout.write(j.status||''); }
  catch(e){ process.stdout.write(''); }
});" 2>/dev/null || echo "")
  case "$WS_STATUS" in
    dry-run|migration-required) DRY_RUN=1 ;;
  esac
fi

# ── Report ───────────────────────────────────────────────────────────────────
if [ "$LEGACY_FOUND" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  [ "$QUIET" -eq 0 ] && echo "OK: n8nac workspace is on the current v2.2 storage model — no migration pending."
  exit 0
fi

echo "=== n8nac Workspace Migration Required ==="
echo ""

if [ "$LEGACY_FOUND" -eq 1 ]; then
  echo "⚠️  Workspace-local n8nac config detected: $REPO_DIR/n8nac-config.json (version=${LEGACY_VERSION})"
  case "$LEGACY_VERSION" in
    1|2)
      echo "    This file uses the pre-2.2 schema. n8nac >= 2.2 no longer reads workspace-local config."
      ;;
    4)
      echo "    Schema is current (v4) but n8nac >= 2.2 expects this file in user home, not in the workspace."
      ;;
    *)
      echo "    Unrecognized schema version. n8nac >= 2.2 expects config in user home, not in the workspace."
      ;;
  esac
  echo ""
  echo "    Recommended migration (moves config to ~/n8nac-config.json + ~/.n8n-manager/):"
  echo "      npx n8nac workspace migrate-v1 --json    # dry-run, inspect changes"
  echo "      npx n8nac workspace migrate-v1 --write   # apply"
  echo ""
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "⚠️  n8nac workspace status reports: ${WS_STATUS}"
  echo "    A v3 → v4 storage finalization is pending. Until you apply it, some"
  echo "    workspace-resolved commands may behave unexpectedly."
  echo ""
  echo "    Recommended migration:"
  echo "      npx n8nac workspace migrate --json       # dry-run, inspect changes"
  echo "      npx n8nac workspace migrate --write      # apply"
  echo ""
fi

echo "After applying, verify by re-opening Claude Code in this workspace —"
echo "the SessionStart hook will re-run setup-check automatically. Or invoke:"
echo "  /n8n-autopilot:check-mcps"
echo ""
echo "(This check is informational only — migration is NOT auto-executed because"
echo " it moves files on your filesystem. Run the commands above when ready.)"

# Always exit 0 — informational, must not block SessionStart.
exit 0
