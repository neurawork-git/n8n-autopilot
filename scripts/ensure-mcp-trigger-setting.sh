#!/usr/bin/env bash
# ensure-mcp-trigger-setting.sh
#
# PreToolUse guard: called before every `npx n8nac push` command.
# If the target workflow contains mcpTrigger, ensures the @workflow setting
# `availableInMCP: true` is set, preventing n8n API bug #25987 from silently
# resetting it to false on every update.
#
# This script is about the WORKFLOW SETTING, not about MCP server reachability
# (that is covered by setup-check.sh + check-mcps skill).
#
# Behavior:
#   availableInMCP: false  → auto-fix to true (silent)
#   availableInMCP missing → warn with clear instructions (non-blocking)
#   availableInMCP: true   → no-op
#
# Called with: bash ensure-mcp-trigger-setting.sh "$CLAUDE_TOOL_INPUT"
# $CLAUDE_TOOL_INPUT is JSON: {"command": "npx n8nac push workflows/foo.workflow.ts ..."}

INPUT="$1"

# Extract workflow file path from command string inside the JSON input
# Matches both relative (workflows/...) and absolute (/Users/.../workflows/...) paths
WORKFLOW_FILE=$(echo "$INPUT" | grep -oE '[^"[:space:]\\]+\.workflow\.ts' | head -1)

[ -z "$WORKFLOW_FILE" ] && exit 0
[ ! -f "$WORKFLOW_FILE" ] && exit 0

# Only act on workflows that use mcpTrigger
if ! grep -qE 'mcpTrigger|n8n-nodes-langchain\.mcpTrigger' "$WORKFLOW_FILE"; then
  exit 0
fi

# Already correct — nothing to do
if grep -qE 'availableInMCP[[:space:]]*:[[:space:]]*true' "$WORKFLOW_FILE"; then
  exit 0
fi

# Auto-fix: false → true (safe string replacement)
if grep -qE 'availableInMCP[[:space:]]*:[[:space:]]*false' "$WORKFLOW_FILE"; then
  # macOS sed requires '' after -i; Linux sed requires no argument — handle both
  if sed --version 2>/dev/null | grep -q GNU; then
    sed -i 's/availableInMCP[[:space:]]*:[[:space:]]*false/availableInMCP: true/g' "$WORKFLOW_FILE"
  else
    sed -i '' 's/availableInMCP[[:space:]]*:[[:space:]]*false/availableInMCP: true/g' "$WORKFLOW_FILE"
  fi
  echo "⚙️  [mcp-guard] Auto-fixed: availableInMCP false → true in $WORKFLOW_FILE" >&2
  exit 0
fi

# availableInMCP is completely absent — warn, do not auto-inject (avoids TS parse errors)
echo "" >&2
echo "⚠️  [mcp-guard] mcpTrigger detected but availableInMCP is not set in @workflow settings:" >&2
echo "   File: $WORKFLOW_FILE" >&2
echo "" >&2
echo "   Without this setting, n8n's API will silently reset availableInMCP to false" >&2
echo "   on every push (n8n bug #25987, fixed in n8n ≥ 2.17.0)." >&2
echo "" >&2
echo "   Add to your @workflow settings block:" >&2
echo "     availableInMCP: true," >&2
echo "" >&2
# Non-blocking: push continues, but user is informed
exit 0
