#!/usr/bin/env bash
# check-custom-nodes-resolution.sh
# Warns when workflows reference COMMUNITY node types but n8nac has no custom-node source loaded.
#
# Why this exists: with `customNodesLoaded: false`, `skills search` and `skills node-info` do not
# error on a community type — they return a confident empty or unrelated result, and
# `validate --strict` calls the type unknown. Every downstream consumer (Phase 0 research, the
# author agent) then treats a node that runs fine in production as nonexistent. The failure is
# silent, which is exactly why it needs a probe.
#
# INFO only — deliberately no AUTOPILOT_ACTION_REQUIRED. Populating n8nac-custom-nodes.json is not
# something the plugin can do for you (see the probe/action symmetry rule in CLAUDE.md); pull-schemas
# fills the plugin's OWN schema cache, which is a different mechanism and does not switch this on.
#
# Usage:
#   bash scripts/check-custom-nodes-resolution.sh          # full report
#   bash scripts/check-custom-nodes-resolution.sh --quiet  # only print when unresolved types exist
#
# Called by: hooks/hooks.json SessionStart (quiet mode)

QUIET=0
[[ "$1" == "--quiet" ]] && QUIET=1

REPO_DIR="$PWD"
[ -d "$REPO_DIR/workflows" ] || exit 0
command -v npx >/dev/null 2>&1 || exit 0

# ── 1. Which community node types do the workflows actually use? ────────────────
# Community == not core (`n8n-nodes-base.`) and not the bundled LangChain pack.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISCOVER="$SCRIPT_DIR/../skills/pull-schemas/scripts/discover-types.sh"
[ -f "$DISCOVER" ] || exit 0

COMMUNITY=$(bash "$DISCOVER" "$REPO_DIR" 2>/dev/null \
  | grep -vE "^n8n-nodes-base\." \
  | grep -vE "^@n8n/n8n-nodes-langchain\." \
  | sed -E 's/\.[^.]+$//' \
  | sort -u)

if [ -z "$COMMUNITY" ]; then
  [ "$QUIET" -eq 0 ] && echo "OK: no community node types referenced in workflows/."
  exit 0
fi

# ── 2. Does n8nac have a custom-node source loaded? ─────────────────────────────
# `skills list --nodes --debug` is the only surface that reveals this.
# The customNodes block goes to STDERR; stdout carries the ~44k-line node index. Read stderr only
# (`2>&1 1>/dev/null`) and scrape the fields — the two streams together are not one parseable document.
DEBUG_HEAD=$(npx --yes n8nac skills list --nodes --debug 2>&1 1>/dev/null | head -40)
if [ -z "$DEBUG_HEAD" ]; then
  [ "$QUIET" -eq 0 ] && echo "INFO: check-custom-nodes-resolution: skipping (n8nac skills list unavailable)."
  exit 0
fi

scrape() { printf "%s" "$DEBUG_HEAD" | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*[^,]+" | head -1 | sed -E "s/^[^:]+:[[:space:]]*//; s/^\"//; s/\"$//"; }

RAW_LOADED=$(scrape customNodesLoaded)
if [ -z "$RAW_LOADED" ]; then
  LOADED=$(printf "unknown\n")
else
  LOADED=$(printf "%s\n%s\n%s\n%s\n" \
    "$([ "$RAW_LOADED" = "true" ] && echo yes || echo no)" \
    "$(scrape customNodeCount)" \
    "$(scrape source)" \
    "$(scrape defaultPath | sed 's/\\\\/\\/g')")
fi

STATE=$(printf "%s" "$LOADED" | sed -n '1p')
[ "$STATE" = "yes" ] && { [ "$QUIET" -eq 0 ] && echo "OK: custom nodes loaded ($(printf "%s" "$LOADED" | sed -n '2p') node(s), source=$(printf "%s" "$LOADED" | sed -n '3p'))."; exit 0; }
[ "$STATE" = "unknown" ] && { [ "$QUIET" -eq 0 ] && echo "INFO: could not parse 'skills list --nodes --debug'."; exit 0; }

DEFAULT_PATH=$(printf "%s" "$LOADED" | sed -n '4p')
COUNT=$(printf "%s\n" "$COMMUNITY" | grep -c .)

echo "=== Community Node Resolution ==="
echo "INFO: workflows/ reference $COUNT community node package(s), but n8nac has NO custom-node"
echo "      source loaded (customNodesLoaded=false, customNodeCount=0):"
printf "%s\n" "$COMMUNITY" | sed 's/^/  · /'
echo ""
echo "      Consequence: 'skills search' / 'skills node-info' return EMPTY for these types instead of"
echo "      erroring, and 'validate --strict' reports them as unknown. An empty research result for one"
echo "      of these packages is a resolution failure, not proof the node does not exist."
echo ""
echo "      Fix — point n8nac at a custom-node definition file:"
echo "        • create ${DEFAULT_PATH:-<repo>/n8nac-custom-nodes.json}, or"
echo "        • register an existing one: npx n8nac env update <env> --custom-nodes-path <path>"
echo "      Verify with: npx n8nac skills list --nodes --debug   (expect customNodesLoaded: true)"
echo ""
echo "      Note: /n8n-autopilot:pull-schemas does NOT fix this — it fills the plugin's own schema"
echo "      cache, a separate mechanism from n8nac's custom-node resolution."
exit 1
