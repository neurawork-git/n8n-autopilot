#!/usr/bin/env bash
# check-inventory-freshness.sh — Warn if docs/INVENTORY.md is missing or older than STALE_DAYS

STALE_DAYS="${INVENTORY_STALE_DAYS:-7}"
INVENTORY="docs/INVENTORY.md"

if [ ! -f "$INVENTORY" ]; then
  echo "INFO: No inventory found — run \`/n8n-autopilot:inventory\` to generate docs/INVENTORY.md"
  exit 0
fi

# Get file modification time in seconds since epoch (portable: macOS + Linux)
if stat -f %m "$INVENTORY" &>/dev/null; then
  FILE_MTIME=$(stat -f %m "$INVENTORY")   # macOS
else
  FILE_MTIME=$(stat -c %Y "$INVENTORY")   # Linux
fi

NOW=$(date +%s)
AGE_DAYS=$(( (NOW - FILE_MTIME) / 86400 ))

if [ "$AGE_DAYS" -ge "$STALE_DAYS" ]; then
  echo "INFO: Inventory is ${AGE_DAYS} day(s) old — run \`/n8n-autopilot:inventory\` to refresh docs/INVENTORY.md"
fi
