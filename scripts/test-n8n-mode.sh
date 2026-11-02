#!/usr/bin/env bash
# test-n8n-mode.sh — self-test for the per-session n8n mode (scripts/lib/n8n-mode.sh) and the hooks
# that depend on it: SessionStart guard/hint, PreToolUse auto-enable + fast path, Stop feedback gate,
# feedback capture. Works in a throwaway temp dir only; touches no real repo and no instance.
#
#   bash scripts/test-n8n-mode.sh
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/n8n-mode-test-$$")"
mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
export N8N_AUTOPILOT_STATE_DIR="$T/state"
unset N8N_AUTOPILOT_MODE N8NAC_ENVIRONMENT N8N_AUTOPILOT_NO_FEEDBACK N8N_AUTOPILOT_NO_FEEDBACK_GATE 2>/dev/null || true

PASS=0; FAIL=0
check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 — expected [$2], got [$3]"; fi
}

# ── fixtures ────────────────────────────────────────────────────────────────
mkdir -p "$T/mono/n8n/workflows/env1" "$T/mono/n8n/.claude" "$T/mono/docs" \
         "$T/dedicated/workflows/env1" "$T/cfgroot" "$T/modefile/.n8n-autopilot" "$T/plain/src" \
         "$T/strayts/.claude/notes"
touch "$T/mono/n8n/workflows/env1/a.workflow.ts" "$T/dedicated/workflows/env1/a.workflow.ts" \
      "$T/strayts/.claude/notes/x.workflow.ts"
echo '{ "env": { "N8NAC_ENVIRONMENT": "env1" } }' > "$T/mono/n8n/.claude/settings.json"
echo '{}' > "$T/cfgroot/n8nac-config.json"
echo 'always' > "$T/modefile/.n8n-autopilot/mode"

guard() { CLAUDE_PROJECT_DIR="$1" bash "$HERE/n8n-mode.sh" guard >/dev/null 2>&1; echo $?; }
hint()  { CLAUDE_PROJECT_DIR="$1" bash "$HERE/n8n-mode.sh" hint 2>/dev/null | grep -c 'n8n mode is off'; }

# ── 1. always-on classification (SessionStart guard) ───────────────────────
check "guard: monorepo root is not always-on"          1 "$(guard "$T/mono")"
check "guard: monorepo n8n/ opened as project is on"   0 "$(guard "$T/mono/n8n")"
check "guard: dedicated repo (workflows/ in root)"     0 "$(guard "$T/dedicated")"
check "guard: n8nac-config.json in root"               0 "$(guard "$T/cfgroot")"
check "guard: .n8n-autopilot/mode = always"            0 "$(guard "$T/modefile")"
check "guard: plain repo"                              1 "$(guard "$T/plain")"
check "guard: stray workflow.ts outside workflows/"    1 "$(guard "$T/strayts")"
check "guard: N8N_AUTOPILOT_MODE=always"               0 "$(N8N_AUTOPILOT_MODE=always guard "$T/plain")"
check "guard: N8N_AUTOPILOT_MODE=off beats dedicated"  1 "$(N8N_AUTOPILOT_MODE=off guard "$T/dedicated")"

# ── 2. SessionStart hint ────────────────────────────────────────────────────
check "hint: monorepo root gets one line"              1 "$(hint "$T/mono")"
check "hint: dedicated repo stays silent"              0 "$(hint "$T/dedicated")"
check "hint: plain repo stays silent"                  0 "$(hint "$T/plain")"
check "hint: mode=off stays silent"                    0 "$(N8N_AUTOPILOT_MODE=off hint "$T/mono")"

# ── 3. "runs n8nac" detection ──────────────────────────────────────────────
. "$HERE/lib/n8n-mode.sh"
runs() { n8n_mode_is_n8nac_call "$1" && echo yes || echo no; }
for c in 'npx n8nac push a.workflow.ts' 'npx -y n8nac@2.7.0 --env e list' 'npx --yes n8nac list' \
         'cd n8n && npx n8nac list' 'N8NAC_ENVIRONMENT=e npx n8nac list' 'N8NAC_ENVIRONMENT=e n8nac list' \
         'n8nac --version' 'foo; n8nac pull 1' '(cd n8n; npx n8nac list)'; do
  check "runs n8nac: $c" yes "$(runs "$c")"
done
# Known limit: `npx n8nac` inside a quoted string counts as a call (no shell parsing). Harmless — it
# only switches the mode on; the Stop gate still needs 3 such calls.
for c in 'grep -rn n8nac docs' 'cat n8nac-config.json' 'git log --grep n8nac' 'ls n8nac-custom-nodes.json' \
         'rg n8nac'; do
  check "mentions only: $c" no "$(runs "$c")"
done

# ── 4. PreToolUse: fast path + auto-enable ─────────────────────────────────
pre() { # pre <sid> <command> [env...] — prints exit code
  local sid="$1" cmd="$2"; shift 2
  local json; json="$(node -e 'console.log(JSON.stringify({session_id:process.argv[1],tool_name:"Bash",tool_input:{command:process.argv[2]}}))' "$sid" "$cmd")"
  ( cd "$T/plain" && printf '%s' "$json" | env "$@" CLAUDE_PROJECT_DIR="$T/plain" bash "$HERE/pretooluse-gate.sh" >/dev/null 2>&1; echo $? )
}
marker() { [ -f "$N8N_AUTOPILOT_STATE_DIR/$1" ] && echo on || echo off; }
check "pretool: unrelated command passes"              0 "$(pre s-fast 'git status')"
check "pretool: unrelated command sets no marker"      off "$(marker s-fast)"
check "pretool: grep n8nac sets no marker"             off "$(pre s-grep 'grep -rn n8nac docs' >/dev/null; marker s-grep)"
pre s-run 'npx n8nac --version' >/dev/null
check "pretool: n8nac call switches mode on"           on "$(marker s-run)"
check "pretool: marker reason is auto"                 auto "$(cat "$N8N_AUTOPILOT_STATE_DIR/s-run" 2>/dev/null)"
pre s-off 'npx n8nac --version' N8N_AUTOPILOT_MODE=off >/dev/null
check "pretool: mode=off is respected"                 off "$(marker s-off)"
check "pretool: env use still blocked (gates intact)"  2 "$(pre s-run 'npx n8nac env use prod')"

# ── 5. Stop feedback gate ───────────────────────────────────────────────────
mkdir -p "$T/stopws"
tx() { # tx <file> <n hint lines> <n real calls> <n grep calls>
  : > "$1"
  local i
  for i in $(seq 1 "$2"); do echo '{"type":"attachment","content":"run npx n8nac env list"}' >> "$1"; done
  for i in $(seq 1 "$3"); do echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"npx n8nac push a.workflow.ts"}}]}}' >> "$1"; done
  for i in $(seq 1 "$4"); do echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"grep -rn n8nac docs"}}]}}' >> "$1"; done
}
tx "$T/noise.jsonl" 6 0 0; tx "$T/greps.jsonl" 0 0 5; tx "$T/real.jsonl" 2 3 0
stopgate() { # stopgate <sid> <transcript> [active] — prints "block" or "pass"
  local out
  out="$(printf '{"session_id":"%s","transcript_path":"%s","stop_hook_active":%s}' "$1" "$2" "${3:-false}" \
        | CLAUDE_PROJECT_DIR="$T/stopws" bash "$HERE/suggest-feedback.sh" 2>/dev/null)"
  case "$out" in *'"decision":"block"'*) echo block ;; *) echo pass ;; esac
}
n8n_mode_enable s-on test
check "stop: hint lines only, mode on"                 pass "$(stopgate s-on "$T/noise.jsonl")"
check "stop: grep calls only, mode on"                 pass "$(stopgate s-on "$T/greps.jsonl")"
check "stop: real calls, mode off"                     pass "$(stopgate s-none "$T/real.jsonl")"
check "stop: real calls, stop_hook_active"             pass "$(stopgate s-on "$T/real.jsonl" true)"
check "stop: real calls, mode on → offers feedback"    block "$(stopgate s-on "$T/real.jsonl")"
check "stop: fires only once per session"              pass "$(stopgate s-on "$T/real.jsonl")"

# ── 6. feedback capture (SessionEnd / PreCompact) ──────────────────────────
# Paths inside hook JSON are native (Claude Code on Windows sends C:\…); Git-Bash /tmp paths are
# not translated inside stdin, so convert them the way the client would.
nat() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
cap() { # cap <sid> <workspace> — prints whether events.ndjson exists afterwards
  mkdir -p "$2"
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","reason":"other"}' "$1" "$(nat "$T/real.jsonl")" "$(nat "$2")" \
    | CLAUDE_PROJECT_DIR="$2" bash "$HERE/capture-feedback.sh" >/dev/null 2>&1
  [ -f "$2/.n8n-autopilot/feedback/events.ndjson" ] && echo written || echo none
}
check "capture: mode off writes nothing"               none "$(cap s-none "$T/capoff")"
check "capture: mode on records the session"           written "$(cap s-on "$T/capon")"
# Monorepo root session: feedback goes to n8n/ (covered by its .gitignore), never the repo root.
check "capture: monorepo root writes nothing at root"  none "$(cap s-on "$T/mono")"
check "capture: monorepo root writes into n8n/"        yes "$([ -f "$T/mono/n8n/.n8n-autopilot/feedback/events.ndjson" ] && echo yes || echo no)"
n8n_mode_enable s-mono test
out="$(printf '{"session_id":"s-mono","transcript_path":"%s","stop_hook_active":false}' "$(nat "$T/real.jsonl")" \
      | CLAUDE_PROJECT_DIR="$T/mono" bash "$HERE/suggest-feedback.sh" 2>/dev/null)"
check "stop: monorepo root marker lands in n8n/"       yes "$([ -f "$T/mono/n8n/.n8n-autopilot/feedback/.suggested-s-mono" ] && [ ! -d "$T/mono/.n8n-autopilot" ] && echo yes || echo no)"

# ── 7. n8n-mode.sh on/off/status (skill entry point) ───────────────────────
st() { CLAUDE_PROJECT_DIR="$T/mono" bash "$HERE/n8n-mode.sh" status "$1" 2>/dev/null | cut -d' ' -f3; }
check "status: fresh session in monorepo root"         OFF "$(st s-cli)"
CLAUDE_PROJECT_DIR="$T/mono" N8N_AUTOPILOT_NO_PROBES=1 bash "$HERE/n8n-mode.sh" on s-cli > "$T/on.out" 2>&1
check "on: switches the session on"                    ON "$(st s-cli)"
check "on: finds the n8n/ workspace"                   1 "$(grep -c '^n8n workspace: n8n ' "$T/on.out")"
check "on: takes N8NAC_ENVIRONMENT from n8n/.claude"   1 "$(grep -c '^N8NAC_ENVIRONMENT=env1 ' "$T/on.out")"
CLAUDE_PROJECT_DIR="$T/mono" bash "$HERE/n8n-mode.sh" off s-cli >/dev/null 2>&1
check "off: switches the session off"                  OFF "$(st s-cli)"
check "on: refused while N8N_AUTOPILOT_MODE=off"       1 "$(CLAUDE_PROJECT_DIR="$T/mono" N8N_AUTOPILOT_MODE=off bash "$HERE/n8n-mode.sh" on s-x >/dev/null 2>&1; echo $?)"
check "on: refused without session id"                 1 "$(CLAUDE_PROJECT_DIR="$T/mono" bash "$HERE/n8n-mode.sh" on '' >/dev/null 2>&1; echo $?)"

echo "n8n-mode: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
