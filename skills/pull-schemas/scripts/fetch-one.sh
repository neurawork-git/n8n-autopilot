#!/usr/bin/env bash
# fetch-one.sh — Pull schema for a single node type via `npx n8nac skills node-info`.
# Output file: schemas/nodes/<type>.json (or schemas/nodes/<scope>/<pkg>.<name>.json for scoped).
# Exit codes:
#   0  schema written
#   1  not found in n8nac index — caller should fall back to fetch-pkg.sh
#   2  CLI error / unexpected
#
# Usage:
#   bash fetch-one.sh <node-type> [workspace-root]

set -u

NODE_TYPE="${1:?node type required}"
ROOT="${2:-$PWD}"
OUT_DIR="${ROOT%/}/schemas/nodes"

mkdir -p "$OUT_DIR"

# Build target filename. Scoped types ('@scope/pkg.name') → subdir per scope; unscoped → flat.
case "$NODE_TYPE" in
  @*)
    SCOPE="${NODE_TYPE%%/*}"
    REST="${NODE_TYPE#*/}"
    mkdir -p "$OUT_DIR/$SCOPE"
    OUT_FILE="$OUT_DIR/$SCOPE/$REST.json"
    ;;
  *)
    OUT_FILE="$OUT_DIR/$NODE_TYPE.json"
    ;;
esac

TMP="$(mktemp)"
if ! npx --yes n8nac skills node-info "$NODE_TYPE" --json >"$TMP" 2>/dev/null; then
  rm -f "$TMP"
  exit 2
fi

# Detect "not found" payload. n8nac returns JSON with `error` or empty body when missing.
if [ ! -s "$TMP" ] || grep -qE '"error"|"not found"|^null$' "$TMP" 2>/dev/null; then
  rm -f "$TMP"
  exit 1
fi

mv "$TMP" "$OUT_FILE"
echo "wrote $OUT_FILE"
exit 0
