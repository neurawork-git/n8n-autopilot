#!/usr/bin/env bash
# test-pretooluse-gate.sh — does the PreToolUse dispatcher block what it must, for BOTH shell
# tools, from the stdin JSON Claude Code actually sends? Run after any change to hooks.json,
# pretooluse-gate.sh or a gate script.
#
# Every case is fed as {"tool_name": …, "tool_input": {"command": …}} on stdin — no argument, no
# CLAUDE_TOOL_INPUT (which does not exist; reading it kept every gate silent until 5.6.0).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/pretooluse-gate.sh"
PASS=0; FAIL=0

run() { # run <tool> <command> <expected-exit> <expected-stderr-regex> <label>
  local tool="$1" cmd="$2" want="$3" pat="$4" label="$5" out rc
  local json
  json=$(node -e 'console.log(JSON.stringify({tool_name: process.argv[1], tool_input: {command: process.argv[2]}, cwd: process.cwd()}))' "$tool" "$cmd")
  out=$(printf '%s' "$json" | env -u N8NAC_ENVIRONMENT -u CLAUDE_TOOL_INPUT -u N8N_AUTOPILOT_ALLOW_LOCAL_WINS -u N8N_AUTOPILOT_SKIP_LINT bash "$GATE" 2>&1); rc=$?
  if [ "$rc" = "$want" ] && { [ -z "$pat" ] || printf '%s' "$out" | grep -qE "$pat"; }; then
    PASS=$((PASS+1)); echo "ok   $label (exit $rc)"
  else
    FAIL=$((FAIL+1)); echo "FAIL $label — exit $rc (want $want), output: $(printf '%s' "$out" | head -2 | tr '\n' ' ')"
  fi
}

run Bash       'echo hello'                                                      0 ''                      'unrelated Bash command passes'
run PowerShell 'Get-ChildItem'                                                   0 ''                      'unrelated PowerShell command passes'
run Bash       'npx n8nac skills validate x.workflow.ts --strict'                0 ''                      'local n8nac subcommand passes without env'
run Bash       'npx n8nac list --json'                                           2 'enforce-env\] BLOCKED' 'Bash: instance command without env is blocked'
run PowerShell 'npx n8nac list --json'                                           2 'enforce-env\] BLOCKED' 'PowerShell: instance command without env is blocked'
run Bash       'N8NAC_ENVIRONMENT=dev npx n8nac list --json'                     0 ''                      'inline env pin passes enforce-env'
run Bash       'npx n8nac env use dev'                                           2 'env use'               'env use is blocked (clobber guard)'
run Bash       'curl -s https://n8n.example.com/api/v1/workflows'                2 'BLOCKED: Use n8nac'    'Bash: direct REST call is blocked'
run PowerShell 'Invoke-RestMethod https://n8n.example.com/api/v1/workflows'      2 'BLOCKED: Use n8nac'    'PowerShell: direct REST call is blocked'
run Bash       'curl -s https://n8n.example.com/api/v1/data-tables'              0 ''                      'data-tables carve-out passes the curl block'
run Bash       'N8NAC_ENVIRONMENT=dev npx n8nac resolve abc123DEF456 --mode keep-current' 2 'push-gate\] BLOCKED' 'resolve keep-current is blocked'
run Bash       'N8NAC_ENVIRONMENT=dev npx n8nac push "no such file.workflow.ts" --verify' 2 'push-lint\] BLOCKED' 'push of an unresolvable file is blocked by push-lint'

# Command forms that slipped past the gates before 5.7.1 (lib/normalize-n8nac-cmd.mjs).
run Bash       'npx -y n8nac@2.7.0 skills validate x.workflow.ts --strict'       0 ''                      'version pin: local subcommand passes without env'
run Bash       'npx -y n8nac@2.7.0 list --json'                                  2 'enforce-env\] BLOCKED' 'version pin: instance command without env is blocked'
run Bash       'npx -y n8nac@2.7.0 env use dev'                                  2 'env use'               'version pin: env use is blocked (clobber guard)'
run Bash       'npx n8nac --env dev list --json'                                 0 ''                      'global --env flag passes enforce-env'
run Bash       'npx n8nac --env dev push "no such file.workflow.ts" --verify'    2 'push-lint\] BLOCKED' 'global --env flag: push still reaches push-lint'
run Bash       'npx -y n8nac@2.7.0 --env=dev push "no such file.workflow.ts"'    2 'push-lint\] BLOCKED' 'version pin + --env=: push still reaches push-lint'
run Bash       'N8NAC_ENVIRONMENT=dev npx n8nac@2.7.0 resolve abc123DEF456 --mode keep-current' 2 'push-gate\] BLOCKED' 'version pin: resolve keep-current is blocked'
run Bash       'cd no-such-dir-xyz && npx n8nac --version'                       0 ''                      'leading cd into a missing dir does not block a local command'
run Bash       'cd no-such-dir-xyz ; npx n8nac --env dev push "no such file.workflow.ts"' 2 'push-lint\] BLOCKED' 'missing cd dir: push still gated from the current dir'

norm() { node "$HERE/lib/normalize-n8nac-cmd.mjs" "$1" | tr '\0' '|'; }
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   normalize: $1"; else FAIL=$((FAIL+1)); echo "FAIL normalize: $1 — got [$3], want [$2]"; fi; }
chk 'cd + pin + --env' 'N8NAC_ENVIRONMENT=dev npx -y n8nac push workflows/a.workflow.ts|dev|n8n|' "$(norm 'cd n8n && npx -y n8nac@2.7.0 --env dev push workflows/a.workflow.ts')"
chk 'inline env kept' 'N8NAC_ENVIRONMENT=dev npx n8nac list|dev||' "$(norm 'N8NAC_ENVIRONMENT=dev npx n8nac@2.7.0 list')"
chk 'quoted cd target' 'npx n8nac list||my dir|' "$(norm 'cd "my dir" ; npx n8nac list')"
chk 'plain command untouched' 'npx n8nac skills search slack|||' "$(norm 'npx n8nac skills search slack')"

# Legacy argument form (used by the older per-gate self-tests) still works.
out=$(bash "$GATE" 'npx n8nac env use dev' 2>&1 </dev/null); rc=$?
if [ "$rc" = 2 ]; then PASS=$((PASS+1)); echo "ok   argument fallback still blocks (exit 2)"; else FAIL=$((FAIL+1)); echo "FAIL argument fallback — exit $rc"; fi

echo "pretooluse-gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
