#!/bin/bash
# test-probe-symmetry.sh — regression test for the probe/action symmetry rule.
#
# A SessionStart probe may only emit AUTOPILOT_ACTION_REQUIRED when the auto-action it
# names can actually resolve the condition. Two real-world violations motivated this:
#   * check-mirror-drift  flagged workflows whose file was present on disk (n8nac status
#     artefact) — mirror-sync pulled forever without converging.
#   * check-credential-freshness flagged orphan credential references by ID — the fixer
#     joins on NAME inside the pinned project and could never repair them.
#
# Runs each probe in a temp workspace against a stubbed `npx` and asserts on the signal.
# No n8n instance, no network.
#
# Usage: bash scripts/test-probe-symmetry.sh

set -u
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPTS")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
check() { # check <name> <expected-substring-present|absent> <needle> <output>
  local name="$1" mode="$2" needle="$3" out="$4"
  if [ "$mode" = present ]; then
    case "$out" in *"$needle"*) echo "ok   — $name"; PASS=$((PASS+1)); return;; esac
  else
    case "$out" in *"$needle"*) ;; *) echo "ok   — $name"; PASS=$((PASS+1)); return;; esac
  fi
  echo "FAIL — $name"
  echo "       expected $mode: $needle"
  echo "       actual output:"; printf '%s\n' "$out" | sed 's/^/       | /'
  FAIL=$((FAIL+1))
}

# --- stub `npx` -------------------------------------------------------------------
# Emits whatever fixture the current case wrote to $TMP/fixture-{list,creds}.json,
# mimicking n8nac's habit of printing a progress line before the JSON.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/npx" <<'STUB'
#!/bin/bash
for a in "$@"; do
  case "$a" in
    # `list` prints a progress line before the JSON; `credential list` does not.
    credential) cat "$FIXTURE_DIR/fixture-creds.json"; exit 0 ;;
    list)       echo "- Listing workflows..."; cat "$FIXTURE_DIR/fixture-list.json"; exit 0 ;;
  esac
done
exit 0
STUB
chmod +x "$TMP/bin/npx"
export PATH="$TMP/bin:$PATH" FIXTURE_DIR="$TMP"

# --- workspace --------------------------------------------------------------------
WS="$TMP/ws"; mkdir -p "$WS/workflows/env"
printf '// present\n' > "$WS/workflows/env/Present.workflow.ts"

# === 1. mirror drift: file missing on disk -> action required =====================
cat > "$TMP/fixture-list.json" <<'JSON'
[{"id":"aaa","name":"Gone","filename":"Gone.workflow.ts","status":"EXIST_ONLY_REMOTELY","isArchived":false}]
JSON
OUT="$(cd "$WS" && bash "$SCRIPTS/check-mirror-drift.sh" --quiet 2>&1)"
check "real drift emits the mandatory signal" present "AUTOPILOT_ACTION_REQUIRED: /n8n-autopilot:mirror-sync" "$OUT"

# === 2. mirror drift: remote-only BUT file present -> no action ====================
cat > "$TMP/fixture-list.json" <<'JSON'
[{"id":"bbb","name":"Here","filename":"Present.workflow.ts","status":"EXIST_ONLY_REMOTELY","isArchived":false}]
JSON
OUT="$(cd "$WS" && bash "$SCRIPTS/check-mirror-drift.sh" --quiet 2>&1)"
check "phantom remote-only emits NO mandatory signal" absent "AUTOPILOT_ACTION_REQUIRED" "$OUT"
check "phantom remote-only still reports the workflow"  present "Here" "$OUT"

# --- credential cases -------------------------------------------------------------
# The probe under test decides purely on the fixer's exit code (3 == "would rewrite").
# fix-workflows.js resolves the live instance itself and ignores the PATH shim, so the
# fixer is stubbed at $CLAUDE_PLUGIN_ROOT: this isolates the probe's own decision.
mkdir -p "$TMP/fakeroot/skills/sync-credentials/scripts"
FAKE_FIXER="$TMP/fakeroot/skills/sync-credentials/scripts/fix-workflows.js"
stub_fixer() { printf 'process.exit(%s)\n' "$1" > "$FAKE_FIXER"; }

cat > "$WS/workflows/env/Cred.workflow.ts" <<'TS'
credentials: { openAiApi: { id: 'STALEID0000000a', name: 'Some account' } },
TS
cat > "$TMP/fixture-creds.json" <<'JSON'
[{"id":"LIVEID0000000aa","name":"Some account","type":"openAiApi","homeProject":{"id":"P1","name":"Proj"}}]
JSON

# === 3. fixer says "I would rewrite this" (exit 3) -> action required ==============
stub_fixer 3
OUT="$(cd "$WS" && CLAUDE_PLUGIN_ROOT="$TMP/fakeroot" bash "$SCRIPTS/check-credential-freshness.sh" --quiet 2>&1)"
check "fixable stale credential emits the mandatory signal" present "AUTOPILOT_ACTION_REQUIRED: /n8n-autopilot:sync-credentials --fix-workflows" "$OUT"

# === 4. fixer says "nothing to rewrite" (exit 0) -> orphan, no action ==============
stub_fixer 0
OUT="$(cd "$WS" && CLAUDE_PLUGIN_ROOT="$TMP/fakeroot" bash "$SCRIPTS/check-credential-freshness.sh" --quiet 2>&1)"
check "orphan credential emits NO mandatory signal" absent "AUTOPILOT_ACTION_REQUIRED" "$OUT"
check "orphan credential is still reported as STALE" present "STALE" "$OUT"

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
