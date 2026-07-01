#!/usr/bin/env bash
# check-plugin-version.sh — SessionStart staleness probe for the n8n-autopilot plugin itself.
#
# A consumer repo ran a stale install (v4.2.2) weeks after v4.8.0 shipped the env-gate hook, so the
# gotcha enforcement silently wasn't there. Plugins do not auto-update — this nudges the user when
# the installed version is behind the latest GitHub release of its own `repository`.
#
# INFO only (never AUTOPILOT_ACTION_REQUIRED): `claude plugin update` changes the environment and is
# the user's call, not a safe idempotent auto-action. Fire-and-forget: any failure -> silent exit 0.
#
# Self-test: `bash check-plugin-version.sh --selftest` (asserts the version-compare logic).

# is_stale LOCAL LATEST -> exit 0 (true) iff LOCAL is an older version than LATEST.
is_stale() {
  [ "$1" = "$2" ] && return 1
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$2" ]
}

if [ "${1:-}" = "--selftest" ]; then
  fail=0
  is_stale 4.2.2 5.0.0 || { echo "FAIL: 4.2.2 < 5.0.0"; fail=1; }
  is_stale 4.9.0 5.0.0 || { echo "FAIL: 4.9.0 < 5.0.0"; fail=1; }
  is_stale 5.0.0 5.0.0 && { echo "FAIL: 5.0.0 == 5.0.0 should not be stale"; fail=1; }
  is_stale 5.1.0 5.0.0 && { echo "FAIL: 5.1.0 > 5.0.0 should not be stale"; fail=1; }
  is_stale 4.10.0 4.9.0 && { echo "FAIL: 4.10.0 > 4.9.0 (numeric, not lexical)"; fail=1; }
  [ "$fail" = 0 ] && echo "check-plugin-version selftest OK"
  exit "$fail"
fi

# Resolve the installed plugin.json: CLAUDE_PLUGIN_ROOT in a real session, else relative to this script.
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PJ="$ROOT/.claude-plugin/plugin.json"
[ -f "$PJ" ] || exit 0
command -v gh >/dev/null 2>&1 || exit 0
gh auth status >/dev/null 2>&1 || exit 0

# Local version + source repo (owner/name) from the plugin's own metadata — no hardcoded repo.
read -r LOCAL REPO < <(node -e '
  try {
    const p = JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
    const m = String(p.repository||"").match(/github\.com[/:]([^/]+\/[^/.]+)/);
    process.stdout.write((p.version||"")+" "+(m?m[1]:""));
  } catch(e) {}
' "$PJ" 2>/dev/null)
[ -n "$LOCAL" ] && [ -n "$REPO" ] || exit 0

# Latest release tag (strip leading v). Short timeout so SessionStart never stalls.
LATEST=$(gh release view --repo "$REPO" --json tagName -q '.tagName' 2>/dev/null | sed 's/^v//')
[ -n "$LATEST" ] || exit 0

if is_stale "$LOCAL" "$LATEST"; then
  echo "INFO: n8n-autopilot plugin is stale — installed v$LOCAL, latest v$LATEST. Gotcha/env-gate hooks may be missing. Run: claude plugin update n8n-autopilot"
fi
exit 0
