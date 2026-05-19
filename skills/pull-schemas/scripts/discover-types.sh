#!/usr/bin/env bash
# discover-types.sh — Extract distinct n8n node type identifiers referenced in workflows/.
# Output: one type per line on stdout. Empty output when no workflows exist.
# Usage:
#   bash discover-types.sh [workspace-root]
#     workspace-root  Defaults to $PWD.

set -u

ROOT="${1:-$PWD}"
WF_DIR="${ROOT%/}/workflows"

if [ ! -d "$WF_DIR" ]; then
  exit 0
fi

# Match `type: '<value>'` lines where <value> looks like an n8n node type:
#   n8n-nodes-base.*  | n8n-nodes-*.* | @scope/n8n-nodes-*.*
find "$WF_DIR" -type f -name "*.workflow.ts" -print0 2>/dev/null \
  | xargs -0 grep -hE "type:[[:space:]]*'(@[a-zA-Z][^/]+/n8n-nodes-[^']+|n8n-nodes-base\.[^']+|n8n-nodes-[^']+)'" 2>/dev/null \
  | grep -oE "'[^']+'" \
  | tr -d "'" \
  | sort -u
