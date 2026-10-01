#!/usr/bin/env bash
# SessionStart probe: is the local instance cache present and fresh?
#
# INFO only, never AUTOPILOT_ACTION_REQUIRED. Rebuilding hits the instance twice (`list`,
# `credential list`) and takes tens of seconds — far past the SessionStart hook budget. Per the
# probe/action symmetry rule, a probe may only mandate an action it can actually complete, so this
# one reports and names the command instead.
#
# Usage: bash scripts/check-instance-cache.sh [--quiet]

set -uo pipefail

QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1

REPO_DIR="$PWD"
CACHE="$REPO_DIR/.n8n-autopilot/instance-cache.json"
MAX_AGE_HOURS=24

# Only meaningful in a workflow repo. The plugin's own repo and unrelated dirs are not.
if [ ! -d "$REPO_DIR/workflows" ]; then
  exit 0
fi

if [ ! -f "$CACHE" ]; then
  echo "=== Instance Cache ==="
  echo "INFO: no .n8n-autopilot/instance-cache.json — build agents cannot see what already runs on this"
  echo "      instance and will research public templates instead. Build it with:"
  echo "        bash \${CLAUDE_PLUGIN_ROOT}/scripts/build-instance-cache.sh"
  exit 0
fi

NOW=$(date +%s)
MTIME=$(date -r "$CACHE" +%s 2>/dev/null || stat -c %Y "$CACHE" 2>/dev/null || echo "$NOW")
AGE_H=$(( (NOW - MTIME) / 3600 ))

# Read via stdin, not a path inside the -e string: MSYS translates path-shaped ARGUMENTS, not path
# substrings in JS source, so `require('/c/Users/...')` silently resolves to C:\c\Users\... and yields
# an empty env name — which made the mismatch branch below unreachable.
CACHED_ENV=$(node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{process.stdout.write(String(JSON.parse(d).environment.name||''))}catch(e){}})" < "$CACHE" 2>/dev/null)
CUR_ENV="${N8NAC_ENVIRONMENT:-}"

# An env mismatch is worse than staleness: the agents would read a DIFFERENT instance's inventory as
# if it were this one, and confidently reuse ids that do not exist here.
if [ -n "$CUR_ENV" ] && [ -n "$CACHED_ENV" ] && [ "$CUR_ENV" != "$CACHED_ENV" ]; then
  echo "=== Instance Cache ==="
  echo "INFO: cache was built for env '$CACHED_ENV' but this session is on '$CUR_ENV'."
  echo "      Workflow ids and credential names in it belong to a different instance. Rebuild with:"
  echo "        bash \${CLAUDE_PLUGIN_ROOT}/scripts/build-instance-cache.sh"
  exit 0
fi

if [ "$AGE_H" -ge "$MAX_AGE_HOURS" ]; then
  echo "=== Instance Cache ==="
  echo "INFO: instance cache is ${AGE_H}h old (threshold ${MAX_AGE_HOURS}h). Workflows added since then are"
  echo "      invisible to the build agents. Refresh with:"
  echo "        bash \${CLAUDE_PLUGIN_ROOT}/scripts/build-instance-cache.sh"
  exit 0
fi

[ "$QUIET" -eq 0 ] && echo "=== Instance Cache ===" && echo "  OK — ${AGE_H}h old, env '$CACHED_ENV'."
exit 0
