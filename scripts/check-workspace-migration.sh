#!/usr/bin/env bash
# check-workspace-migration.sh
# Reports an in-repo n8nac-config.json and whether it is superseded or LIVE.
# On n8nac 2.5.0 an in-repo v4 config is read by the CLI; with no home config present it is
# the ONLY config, so "delete it" is destructive advice (#22). Never recommend rm.
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
# Its presence alone says nothing: n8nac 2.5.0 reads an in-repo config, and where no
# home config exists it is the live one. Only the combination with §1b decides.
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

# ── 1b. Does a home config exist at all? ────────────────────────────────────
# Decides whether the in-repo file is a leftover or the only configuration there is.
HOME_CONFIG=0
HOME_CONFIG_PATHS=""
if [ -f "$HOME/n8nac-config.json" ]; then
  HOME_CONFIG=1
  HOME_CONFIG_PATHS="~/n8nac-config.json"
fi
if [ -d "$HOME/.n8n-manager" ]; then
  HOME_CONFIG=1
  HOME_CONFIG_PATHS="${HOME_CONFIG_PATHS:+$HOME_CONFIG_PATHS, }~/.n8n-manager/"
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

# An in-repo config that is simply the live one is not a finding. Stay silent in quiet mode
# rather than opening an "Action Required" block every session for a healthy workspace.
if [ "$HOME_CONFIG" -eq 0 ] && [ "$LEGACY_VERSION" = "4" ] && [ "$QUIET" -eq 1 ]; then
  exit 0
fi

if [ "$HOME_CONFIG" -eq 1 ]; then
  echo "=== n8nac Workspace Config — Action Required ==="
else
  echo "=== n8nac Workspace Config ==="
fi
echo ""

if [ "$LEGACY_FOUND" -eq 1 ]; then
  echo "In-repo config present: $REPO_DIR/n8nac-config.json (version=${LEGACY_VERSION})"

  # NEVER recommend deleting it on the strength of its location alone. On n8nac 2.5.0 an in-repo
  # v4 config is a config n8nac actually READS — with no home config present it is the only one,
  # and deleting it destroys every environment binding in the workspace (#22). Decide from what
  # is actually there, and offer a reversible `mv` rather than `rm` even when it is safe.
  if [ "$HOME_CONFIG" -eq 1 ]; then
    case "$LEGACY_VERSION" in
      1|2)
        echo "    Schema is pre-2.2 AND a home config exists ($HOME_CONFIG_PATHS)."
        echo "    This copy is genuinely superseded."
        echo ""
        echo "    SUGGESTED (reversible — verify before discarding):"
        echo "      mv \"$REPO_DIR/n8nac-config.json\" \"$REPO_DIR/n8nac-config.json.bak\""
        echo "      npx n8nac env list --json   # confirm your environments are still there"
        ;;
      *)
        echo "    A home config ALSO exists ($HOME_CONFIG_PATHS) — two configs, unclear precedence."
        echo "    Do not delete either one blind. Determine which is live first:"
        echo "      npx n8nac env list --json"
        echo "      npx n8nac workspace status --json"
        echo "    If the environments you see match this in-repo file, it is the live config."
        ;;
    esac
  else
    echo "    No home config exists (~/n8nac-config.json, ~/.n8n-manager/ both absent),"
    echo "    so n8nac 2.5.0 reads THIS file. It is your live configuration — do not delete it."
    echo "    Verify with: npx n8nac env list --json"
    if [ "$LEGACY_VERSION" != "4" ]; then
      echo ""
      echo "    Schema is ${LEGACY_VERSION}, older than the v4 that 2.5.0 writes. If commands misbehave,"
      echo "    re-create the bindings in a home config FIRST, confirm them, and only then retire this file:"
      echo "      npx n8nac env add <name> --base-url <url> --workflows-path workflows"
      echo "      npx n8nac env auth set <name> --api-key-stdin"
    fi
  fi
  echo ""
fi

echo "Re-check any time with:  /n8n-autopilot:check-mcps"
echo ""
echo "(Informational only. This check never deletes anything and never tells you to —"
echo " an in-repo config can be the live one.)"

# Always exit 0 — informational, must not block SessionStart.
exit 0
