#!/usr/bin/env bash
# n8n-repo-guard.sh — exit 0 when the current project is an n8n workflow repo, exit 1 otherwise.
# SessionStart probes are chained behind it (`bash guard.sh && bash probe.sh`), so a repo that
# never touches n8n sees none of the "env unbound / n8nac not set up" noise (#77).
#
# An n8n repo is any of:
#   - N8NAC_ENVIRONMENT pinned for the session
#   - a *.workflow.ts file (depth ≤ 4, node_modules excluded)
#   - .n8n-autopilot/ · .n8n-state.json · n8nac-config.json · n8nac-custom-nodes.json in the root
#   - CLAUDE.md mentioning n8n-autopilot or n8nac
# Never reads stdin (the probe behind it may need it). Never prints.
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -n "${N8NAC_ENVIRONMENT:-}" ] && exit 0
for f in .n8n-autopilot .n8n-state.json n8nac-config.json n8nac-custom-nodes.json; do
  [ -e "$ROOT/$f" ] && exit 0
done
[ -f "$ROOT/CLAUDE.md" ] && grep -qE 'n8n-autopilot|n8nac' "$ROOT/CLAUDE.md" 2>/dev/null && exit 0
find "$ROOT" -maxdepth 4 -name '*.workflow.ts' -not -path '*/node_modules/*' -print -quit 2>/dev/null | grep -q . && exit 0
exit 1
