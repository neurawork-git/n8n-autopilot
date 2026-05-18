#!/usr/bin/env bash
# setup-check.sh — Verify n8n-autopilot plugin prerequisites
# Run via SessionStart hook or manually: bash scripts/setup-check.sh

set -euo pipefail

ERRORS=0
WARNINGS=0

echo "=== n8n-autopilot Setup Check ==="
echo ""

# ── 1. Node.js / npx ──────────────────────────────────────────────────────────
if ! command -v npx &>/dev/null; then
  echo "ERROR: npx not found. Install Node.js >= 18." >&2
  ERRORS=$((ERRORS + 1))
elif ! npx n8nac --version &>/dev/null 2>&1; then
  echo "WARN: n8nac not installed globally. Will use npx (slower first run)."
  WARNINGS=$((WARNINGS + 1))
fi

# ── 2. n8nac-config.json ──────────────────────────────────────────────────────
if [ ! -f "n8nac-config.json" ]; then
  echo "ERROR: n8nac-config.json not found."
  echo "  Run: cp n8nac-config.json.example n8nac-config.json"
  echo "  Then fill in 'host' and run: npx n8nac init"
  ERRORS=$((ERRORS + 1))
fi

# ── 3. .mcp.json — exists ─────────────────────────────────────────────────────
if [ ! -f ".mcp.json" ]; then
  echo "ERROR: .mcp.json not found."
  echo "  Run: cp .mcp.json.example .mcp.json — n8n-as-code works out-of-the-box."
  ERRORS=$((ERRORS + 1))
else
  # ── 4. MCP server entries present ─────────────────────────────────────────
  if ! grep -q '"n8n-as-code"' .mcp.json 2>/dev/null; then
    echo "ERROR: .mcp.json is missing the 'n8n-as-code' MCP server entry (n8nac skills)."
    echo "  See docs/MCP.md — Section 1 for the required config block."
    ERRORS=$((ERRORS + 1))
  fi

  # ── 5. n8n API connectivity via n8nac ────────────────────────────────────
  if [ -f "n8nac-config.json" ]; then
    N8N_HOST=$(grep -o '"host"[[:space:]]*:[[:space:]]*"[^"]*"' n8nac-config.json 2>/dev/null | head -1 | sed 's/.*: *"\(.*\)"/\1/' || echo "")
    if [ -n "$N8N_HOST" ] && command -v curl &>/dev/null; then
      BASE_URL="${N8N_HOST%/}/api/v1"
      HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
        "${BASE_URL}/workflows?limit=1" 2>/dev/null || echo "000")
      if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "401" ]; then
        echo "OK: n8n API reachable at ${BASE_URL}"
      elif [ "$HTTP_STATUS" = "000" ]; then
        echo "ERROR: n8n instance not reachable at ${BASE_URL}."
        echo "  Is n8n running? Check: docker ps | grep n8n"
        ERRORS=$((ERRORS + 1))
      else
        echo "WARN: n8n API returned HTTP ${HTTP_STATUS} — check n8nac-config.json host."
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
  fi
fi

# ── 6. n8nac version check ───────────────────────────────────────────────────
MIN_N8NAC_VERSION="2.2.0"
if command -v npx &>/dev/null; then
  INSTALLED_N8NAC=$(npx --yes n8nac --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
  if [ -n "$INSTALLED_N8NAC" ]; then
    # Simple semver compare: split into parts
    IFS='.' read -r i_maj i_min i_pat <<< "$INSTALLED_N8NAC"
    IFS='.' read -r m_maj m_min m_pat <<< "$MIN_N8NAC_VERSION"
    if [ "$i_maj" -lt "$m_maj" ] || \
       { [ "$i_maj" -eq "$m_maj" ] && [ "$i_min" -lt "$m_min" ]; } || \
       { [ "$i_maj" -eq "$m_maj" ] && [ "$i_min" -eq "$m_min" ] && [ "$i_pat" -lt "$m_pat" ]; }; then
      echo "WARN: n8nac ${INSTALLED_N8NAC} is below minimum ${MIN_N8NAC_VERSION}."
      echo "  Clear npx cache: npx clear-npx-cache && npx n8nac@latest --version"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
fi

# ── 7. Community node schema coverage ────────────────────────────────────────
echo ""
echo "=== Community Node Schema Check ==="
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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
