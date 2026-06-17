#!/usr/bin/env bash
# setup-check.sh — Verify n8n-autopilot plugin prerequisites
# Run via SessionStart hook or manually: bash scripts/setup-check.sh
#
# ── n8nac compatibility ──────────────────────────────────────────────────────
# REFERENCE_N8NAC_VERSION is the version this plugin was developed and tested
# against. New features (e.g. `workspace status`, `setup --mode`, `credentials
# recipes`, `workflow present`) assume this version.
# MIN_N8NAC_VERSION is the floor below which the plugin will not work at all.
# To bump: change both constants here, then sync README badges + plugin.json.

set -euo pipefail

REFERENCE_N8NAC_VERSION="2.4.0"
MIN_N8NAC_VERSION="2.3.0"

# n8n-autopilot 4.x is CLI-only — no MCP server is required or used. The
# `mcp__n8n-as-code__*` namespace from older versions never had a stable
# upstream source (npm `n8nac mcp` is broken; Etienne's companion plugin
# ships skill knowledge, not an MCP server). All schema research now goes
# through `npx n8nac skills …`.

ERRORS=0
WARNINGS=0

echo "=== n8n-autopilot Setup Check ==="
echo "Reference n8nac: ${REFERENCE_N8NAC_VERSION} (minimum: ${MIN_N8NAC_VERSION})"
echo ""

# ── 1. Node.js / npx ──────────────────────────────────────────────────────────
if ! command -v npx &>/dev/null; then
  echo "ERROR: npx not found. Install Node.js >= 18." >&2
  ERRORS=$((ERRORS + 1))
elif ! npx n8nac --version &>/dev/null 2>&1; then
  echo "WARN: n8nac not installed globally. Will use npx (slower first run)."
  WARNINGS=$((WARNINGS + 1))
fi

# ── 2. n8nac version vs reference ────────────────────────────────────────────
INSTALLED_N8NAC=""
if command -v npx &>/dev/null; then
  INSTALLED_N8NAC=$(npx --yes n8nac --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
  if [ -n "$INSTALLED_N8NAC" ]; then
    IFS='.' read -r i_maj i_min i_pat <<< "$INSTALLED_N8NAC"
    IFS='.' read -r m_maj m_min m_pat <<< "$MIN_N8NAC_VERSION"
    IFS='.' read -r r_maj r_min r_pat <<< "$REFERENCE_N8NAC_VERSION"
    # Below minimum → error
    if [ "$i_maj" -lt "$m_maj" ] || \
       { [ "$i_maj" -eq "$m_maj" ] && [ "$i_min" -lt "$m_min" ]; } || \
       { [ "$i_maj" -eq "$m_maj" ] && [ "$i_min" -eq "$m_min" ] && [ "$i_pat" -lt "$m_pat" ]; }; then
      echo "ERROR: n8nac ${INSTALLED_N8NAC} is below required minimum ${MIN_N8NAC_VERSION}."
      echo "  Clear npx cache: npx clear-npx-cache && npx n8nac@latest --version"
      ERRORS=$((ERRORS + 1))
    # Above reference → warn (untested territory)
    elif [ "$i_maj" -gt "$r_maj" ] || \
         { [ "$i_maj" -eq "$r_maj" ] && [ "$i_min" -gt "$r_min" ]; } || \
         { [ "$i_maj" -eq "$r_maj" ] && [ "$i_min" -eq "$r_min" ] && [ "$i_pat" -gt "$r_pat" ]; }; then
      echo "WARN: n8nac ${INSTALLED_N8NAC} is newer than reference ${REFERENCE_N8NAC_VERSION}."
      echo "  Plugin features may diverge — verify changelogs at https://www.npmjs.com/package/n8nac."
      WARNINGS=$((WARNINGS + 1))
    else
      echo "OK: n8nac ${INSTALLED_N8NAC} (within ${MIN_N8NAC_VERSION}..${REFERENCE_N8NAC_VERSION})"
    fi
  fi
fi

# ── 3. Workspace state (replaces legacy n8nac-config.json file-check) ────────
# `workspace status --json` is the authoritative effective-context resolver
# in n8nac v2.2. It tells us whether a usable n8n instance is bound to the
# current workspace, and whether a migration is pending.
WS_STATE=""
if [ -n "$INSTALLED_N8NAC" ]; then
  WS_JSON=$(npx --yes n8nac workspace status --json 2>/dev/null || echo "")
  if [ -z "$WS_JSON" ]; then
    echo "ERROR: n8nac workspace not initialized."
    echo "  Run: npx n8nac env add <name> --base-url <url> --workflows-path workflows"
    echo "  Then: npx n8nac env auth set <name> --api-key-stdin"
    echo "  Then: npx n8nac env use <name>"
    ERRORS=$((ERRORS + 1))
  else
    # workspace status returns two distinct JSON shapes in n8nac 2.2:
    #   - BOUND:     { version, activeEnvironmentId, activeEnvironment: {...}, ... }   (no `status` field)
    #   - PENDING:   { status: "dry-run" | "migration-required", operations: [...] }
    WS_STATE=$(echo "$WS_JSON" | node -e "
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
  try {
    const j=JSON.parse(d);
    if (j.status) { process.stdout.write(j.status); return; }
    if (j.activeEnvironment && j.activeEnvironment.name) { process.stdout.write('bound:' + j.activeEnvironment.name); return; }
    if (j.version) { process.stdout.write('bound'); return; }
    process.stdout.write('unknown');
  } catch(e) { process.stdout.write('parse-error'); }
});" 2>/dev/null || echo "parse-error")

    case "$WS_STATE" in
      bound|bound:*)
        echo "OK: workspace bound (${WS_STATE})"
        ;;
      dry-run|migration-required)
        echo "WARN: workspace status returned '${WS_STATE}' — the workspace storage is v4-native;"
        echo "  there is no migrate command anymore. If a stray in-repo n8nac-config.json exists,"
        echo "  delete it manually (config now lives in ~/n8nac-config.json + ~/.n8n-manager/)."
        WARNINGS=$((WARNINGS + 1))
        ;;
      *)
        echo "WARN: workspace status returned unexpected shape '${WS_STATE}' — run 'npx n8nac workspace status --json' manually."
        WARNINGS=$((WARNINGS + 1))
        ;;
    esac
  fi
fi

# ── 3b. Effective SESSION env (honors N8NAC_ENVIRONMENT / --env) ─────────────
# `workspace status` resolves only the GLOBAL active env — it ignores
# N8NAC_ENVIRONMENT and --env. `env status --json` resolves the env this session
# actually targets, so the reported host/project match what commands will hit.
ENV_NAME=""; ENV_HOST=""; ENV_PROJECT=""
if [ -n "$INSTALLED_N8NAC" ]; then
  ENV_JSON=$(npx --yes n8nac env status --json 2>/dev/null || echo "")
  if [ -n "$ENV_JSON" ]; then
    IFS=$'\t' read -r ENV_NAME ENV_HOST ENV_PROJECT <<EOF2
$(printf "%s" "$ENV_JSON" | node -e "
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
  try { const i=d.indexOf('{'); const j=JSON.parse(d.slice(i)); const r=j.resolved||j;
    process.stdout.write([(j.name||r.environmentName||''),(r.host||''),(r.projectName||'')].join('\t')); }
  catch(e){}
});" 2>/dev/null)
EOF2
    if [ -n "$ENV_NAME" ]; then
      SRC="N8NAC_ENVIRONMENT"; [ -z "${N8NAC_ENVIRONMENT:-}" ] && SRC="pinned/global"
      echo "OK: session env: ${ENV_NAME} -> ${ENV_HOST} / ${ENV_PROJECT:-<default project>} (via ${SRC})"
    fi
  fi
fi

# ── 4. n8nac CLI smoke test ──────────────────────────────────────────────────
# `set -e` would abort the script on any non-zero exit — wrap probes in `|| true`.
if [ -n "$INSTALLED_N8NAC" ]; then
  CLI_OUT=$(npx --yes n8nac workspace status --json 2>&1 || true)
  if echo "$CLI_OUT" | grep -q '"version"\|"status"'; then
    echo "OK: n8nac CLI smoke (workspace status responds)"
  else
    echo "WARN: n8nac CLI smoke failed (\`workspace status\` returned no parseable JSON)."
    WARNINGS=$((WARNINGS + 1))
  fi
fi

# ── 5. Companion plugin check (n8n-as-code by Etienne Lescot) ────────────────
# n8n-autopilot 4.x delegates schema research / authoring guidance to Etienne's
# `n8n-architect` skill, shipped via the `n8n-as-code@n8nac-marketplace` plugin.
# It is strongly recommended but not strictly required.
USER_SETTINGS="$HOME/.claude/settings.json"
if [ -f "$USER_SETTINGS" ]; then
  if grep -q '"n8n-as-code@n8nac-marketplace"[[:space:]]*:[[:space:]]*true' "$USER_SETTINGS" 2>/dev/null; then
    echo "OK: companion plugin n8n-as-code@n8nac-marketplace enabled"
  else
    echo "WARN: companion plugin n8n-as-code (Etienne Lescot) not enabled — install it for full UX:"
    echo "  claude plugin marketplace add EtienneLescot/n8n-as-code"
    echo "  claude plugin install n8n-as-code@n8nac-marketplace"
    WARNINGS=$((WARNINGS + 1))
  fi
fi

# ── 5. n8n API connectivity (host pulled from workspace status, not file) ────
if command -v curl &>/dev/null; then
  # Prefer the SESSION env host (env status, honors N8NAC_ENVIRONMENT); fall back
  # to the global workspace-status host only if env resolution failed.
  N8N_HOST="$ENV_HOST"
  if [ -z "$N8N_HOST" ] && [ -n "$WS_JSON" ]; then
    N8N_HOST=$(echo "$WS_JSON" | node -e "
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
  try {
    const j=JSON.parse(d);
    if (j.activeEnvironment && Array.isArray(j.environmentTargets)) {
      const tgt = j.environmentTargets.find(t => t.id === j.activeEnvironment.environmentTargetId);
      if (tgt && tgt.url) { process.stdout.write(tgt.url); return; }
    }
    const inst = (j.operations||[]).flatMap(o=>o.instances||[]);
    const url = (inst[0]&&inst[0].url) || j.activeInstanceUrl || j.baseUrl || '';
    process.stdout.write(url);
  } catch(e) { process.stdout.write(''); }
});" 2>/dev/null || echo "")
  fi
  if [ -n "$N8N_HOST" ]; then
    BASE_URL="${N8N_HOST%/}/api/v1"
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
      "${BASE_URL}/workflows?limit=1" 2>/dev/null || echo "000")
    if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "401" ]; then
      echo "OK: n8n API reachable at ${BASE_URL}"
    elif [ "$HTTP_STATUS" = "000" ]; then
      echo "ERROR: n8n instance not reachable at ${BASE_URL}."
      echo "  Is n8n running?"
      ERRORS=$((ERRORS + 1))
    else
      echo "WARN: n8n API returned HTTP ${HTTP_STATUS} — verify host + API key in 'workspace status'."
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
fi

# ── 6. Project visibility (multi-project awareness) ─────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [ -n "${WS_STATE:-}" ] && [[ "$WS_STATE" == bound* ]]; then
  echo ""
  echo "=== Project Visibility ==="
  if command -v node &>/dev/null && [ -f "$PLUGIN_ROOT/skills/find-project/scripts/list.js" ]; then
    node "$PLUGIN_ROOT/skills/find-project/scripts/list.js" 2>/dev/null | sed 's/^/  /' || true
  fi
fi

# ── 7. Community node schema coverage ────────────────────────────────────────
echo ""
echo "=== Community Node Schema Check ==="
bash "$SCRIPT_DIR/check-installed-nodes.sh" 2>/dev/null || WARNINGS=$((WARNINGS + 1))

# ── 8. Inventory freshness ────────────────────────────────────────────────────
bash "$SCRIPT_DIR/check-inventory-freshness.sh" 2>/dev/null

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo "All checks passed. n8n-autopilot is ready."
elif [ "$ERRORS" -eq 0 ]; then
  echo "${WARNINGS} warning(s). n8n-autopilot should work but review the above."
else
  echo "${ERRORS} error(s) found. Fix them before using the plugin." >&2
  exit 1
fi
