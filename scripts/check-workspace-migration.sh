#!/usr/bin/env bash
# check-workspace-migration.sh
# Detects a stray in-repo n8nac-config.json that should be deleted manually.
# (n8nac >= 2.3 stores all config in user home — ~/n8nac-config.json +
# ~/.n8n-manager/. There is no migrate command anymore.)
#
# Surfaces an INFO block to the user. Does NOT auto-execute anything.
# Exits 0 always so it does not block SessionStart.
#
# Usage:
#   bash scripts/check-workspace-migration.sh          # full report
#   bash scripts/check-workspace-migration.sh --quiet  # only print when action needed
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

# ── 1. Workspace-local n8nac-config.json (any format) ──────────────────────
# In n8nac >= 2.3 the workspace config lives entirely in user home
# (~/n8nac-config.json + ~/.n8n-manager/). A copy of n8nac-config.json in the
# repo root is stale and should be deleted manually — there is no migrate command
# to handle this automatically.
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

# ── 2. workspace status — informational only ────────────────────────────────
# workspace status is read-only in n8nac >= 2.3. No migration commands exist
# anymore. We read it purely for informational context; no action is triggered.
WS_JSON=$(npx --yes n8nac workspace status --json 2>/dev/null || echo "")

# ── Report ───────────────────────────────────────────────────────────────────
if [ "$LEGACY_FOUND" -eq 0 ]; then
  [ "$QUIET" -eq 0 ] && echo "OK: no stray in-repo n8nac-config.json found — workspace config is in user home."
  exit 0
fi

echo "=== n8nac Workspace Config — Action Required ==="
echo ""

if [ "$LEGACY_FOUND" -eq 1 ]; then
  echo "WARNING: Stray in-repo config detected: $REPO_DIR/n8nac-config.json (version=${LEGACY_VERSION})"
  case "$LEGACY_VERSION" in
    1|2)
      echo "    This file uses the pre-2.2 schema. n8nac >= 2.3 does not read workspace-local config."
      ;;
    4)
      echo "    Schema is v4 but n8nac >= 2.3 expects all config in user home, not in the workspace."
      ;;
    *)
      echo "    Unrecognized schema version. n8nac >= 2.3 expects all config in user home."
      ;;
  esac
  echo ""
  echo "    ACTION: Delete this file manually:"
  echo "      rm $REPO_DIR/n8nac-config.json"
  echo ""
  echo "    Config now lives in: ~/n8nac-config.json  and  ~/.n8n-manager/"
  echo "    To re-bind an environment, use the env flow:"
  echo "      npx n8nac env add <name> --base-url <url> --workflows-path workflows"
  echo "      npx n8nac env auth set <name> --api-key-stdin"
  echo "      npx n8nac env use <name>"
  echo ""
fi

echo "After cleaning up, verify by re-opening Claude Code in this workspace —"
echo "the SessionStart hook will re-run setup-check automatically. Or invoke:"
echo "  /n8n-autopilot:check-mcps"
echo ""
echo "(This check is informational only — deletion must be done manually.)"

# Always exit 0 — informational, must not block SessionStart.
exit 0
