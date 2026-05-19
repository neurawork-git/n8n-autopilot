#!/usr/bin/env bash
# run.sh — Pull schemas for every node type referenced in the current workspace.
#
# Stage 1: try `npx n8nac skills node-info <type>` for each discovered type.
# Stage 2: for types n8nac does not know, extract straight from the npm package
#          (the package name is the type prefix up to the last dot).
# Stage 3: rebuild schemas/_index.json.
#
# Flags:
#   --core-only            Skip community nodes (anything not prefixed with n8n-nodes-base.)
#   --community-only       Skip core nodes (n8n-nodes-base.*)
#   --nodes <list>         Comma-separated explicit node-type list (skip discovery)
#   --packages <list>      Comma-separated npm package list — jump directly to Stage 2 for each
#   --workspace <dir>      Workspace root (default: $PWD)
#   --no-index             Skip Stage 3 (index rebuild)
#
# Exit codes:
#   0  success (at least one schema fetched)
#   1  bad flags
#   2  no node types found and no --packages provided

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

WORKSPACE="$PWD"
CORE_ONLY=0
COMMUNITY_ONLY=0
EXPLICIT_NODES=""
EXPLICIT_PACKAGES=""
NO_INDEX=0

while [ $# -gt 0 ]; do
  case "$1" in
    --core-only)        CORE_ONLY=1 ;;
    --community-only)   COMMUNITY_ONLY=1 ;;
    --nodes)            shift; EXPLICIT_NODES="${1:-}" ;;
    --packages)         shift; EXPLICIT_PACKAGES="${1:-}" ;;
    --workspace)        shift; WORKSPACE="${1:-}" ;;
    --no-index)         NO_INDEX=1 ;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "ERROR: unknown flag $1" >&2; exit 1 ;;
  esac
  shift
done

mkdir -p "$WORKSPACE/schemas/nodes"

# ── Stage 2 fast-path: explicit --packages list ──────────────────────────────
if [ -n "$EXPLICIT_PACKAGES" ]; then
  echo "=== Stage 2 (explicit packages) ==="
  IFS=',' read -ra PKGS <<< "$EXPLICIT_PACKAGES"
  for pkg in "${PKGS[@]}"; do
    pkg="${pkg// /}"
    [ -z "$pkg" ] && continue
    echo "→ $pkg"
    node "$SCRIPT_DIR/fetch-pkg.js" "$pkg" "$WORKSPACE" || echo "  FAILED: $pkg"
  done
  if [ "$NO_INDEX" -eq 0 ]; then
    echo ""
    echo "=== Stage 3: rebuild index ==="
    node "$SCRIPT_DIR/rebuild-index.js" "$WORKSPACE"
  fi
  exit 0
fi

# ── Discover node types ──────────────────────────────────────────────────────
if [ -n "$EXPLICIT_NODES" ]; then
  TYPES=$(echo "$EXPLICIT_NODES" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$')
else
  TYPES=$(bash "$SCRIPT_DIR/discover-types.sh" "$WORKSPACE")
fi

if [ -z "$TYPES" ]; then
  echo "ERROR: no node types found in $WORKSPACE/workflows/ and no --nodes / --packages given." >&2
  echo "       Add workflow files, or pass --nodes / --packages explicitly." >&2
  exit 2
fi

# Apply scope filters
if [ "$CORE_ONLY" -eq 1 ]; then
  TYPES=$(echo "$TYPES" | grep '^n8n-nodes-base\.' || true)
elif [ "$COMMUNITY_ONLY" -eq 1 ]; then
  TYPES=$(echo "$TYPES" | grep -v '^n8n-nodes-base\.' || true)
fi

if [ -z "$TYPES" ]; then
  echo "WARN: scope filter left no types to fetch."
  exit 0
fi

# ── Stage 1 loop + Stage 2 fallback collection ───────────────────────────────
echo "=== Stage 1: n8nac skills node-info ==="
PKG_FALLBACK=""
OK_COUNT=0
FAIL_COUNT=0

while IFS= read -r type; do
  [ -z "$type" ] && continue
  bash "$SCRIPT_DIR/fetch-one.sh" "$type" "$WORKSPACE" >/dev/null 2>&1
  rc=$?
  case $rc in
    0)
      OK_COUNT=$((OK_COUNT + 1))
      echo "  OK   $type"
      ;;
    1)
      # not in n8nac index — derive package name (everything before last dot)
      pkg="${type%.*}"
      echo "  ?    $type  (will Stage-2 npm-extract $pkg)"
      case ",$PKG_FALLBACK," in
        *",$pkg,"*) ;;
        *) PKG_FALLBACK="$PKG_FALLBACK,$pkg" ;;
      esac
      ;;
    *)
      FAIL_COUNT=$((FAIL_COUNT + 1))
      echo "  FAIL $type  (n8nac CLI error)"
      ;;
  esac
done <<< "$TYPES"

# ── Stage 2: npm-extract uncovered packages ──────────────────────────────────
PKG_FALLBACK="${PKG_FALLBACK#,}"
if [ -n "$PKG_FALLBACK" ]; then
  echo ""
  echo "=== Stage 2: npm extraction for uncovered packages ==="
  IFS=',' read -ra PKGS <<< "$PKG_FALLBACK"
  for pkg in "${PKGS[@]}"; do
    [ -z "$pkg" ] && continue
    echo "→ $pkg"
    if node "$SCRIPT_DIR/fetch-pkg.js" "$pkg" "$WORKSPACE"; then
      OK_COUNT=$((OK_COUNT + 1))
    else
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  done
fi

# ── Stage 3: rebuild index ───────────────────────────────────────────────────
if [ "$NO_INDEX" -eq 0 ]; then
  echo ""
  echo "=== Stage 3: rebuild index ==="
  node "$SCRIPT_DIR/rebuild-index.js" "$WORKSPACE"
fi

echo ""
echo "Done. $OK_COUNT ok, $FAIL_COUNT failed."
exit 0
