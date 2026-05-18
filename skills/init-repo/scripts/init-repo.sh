#!/usr/bin/env bash
# init-repo.sh — Scaffold a new n8n workflow repo for the n8n-autopilot plugin.
#
# Usage:
#   bash skills/init-repo/scripts/init-repo.sh [TARGET_DIR] [--force] [--no-git]
#     TARGET_DIR  Defaults to "." (current dir). If does not exist, will be created.
#     --force     Allow scaffolding into a non-empty dir (only writes missing files).
#     --no-git    Skip `git init`.
#
# Idempotent: refuses to overwrite existing files. Re-run safe.
# Exits 0 on success, non-zero on error.

set -euo pipefail

# ── Resolve skill root ───────────────────────────────────────────────────────
# Script lives at skills/init-repo/scripts/init-repo.sh.
# Templates are colocated at skills/init-repo/assets/templates/.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES_DIR="${SKILL_ROOT}/assets/templates"

if [ ! -d "$TEMPLATES_DIR" ]; then
  echo "ERROR: templates dir not found at $TEMPLATES_DIR" >&2
  exit 1
fi

# ── Parse args ───────────────────────────────────────────────────────────────
TARGET="."
FORCE=0
NO_GIT=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --no-git) NO_GIT=1 ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --*) echo "ERROR: unknown flag $arg" >&2; exit 2 ;;
    *) TARGET="$arg" ;;
  esac
done

mkdir -p "$TARGET"
TARGET_ABS="$(cd "$TARGET" && pwd)"
REPO_NAME="$(basename "$TARGET_ABS")"

echo "=== n8n-autopilot init-repo ==="
echo "Target: $TARGET_ABS"
echo "Name:   $REPO_NAME"
echo ""

# ── Refuse if already bootstrapped ───────────────────────────────────────────
if [ -f "$TARGET_ABS/n8nac-config.json" ]; then
  echo "ERROR: $TARGET_ABS already has n8nac-config.json — already bootstrapped." >&2
  echo "       Delete it manually if you really want to re-init." >&2
  exit 1
fi

# ── Refuse non-empty dir unless --force ──────────────────────────────────────
if [ "$FORCE" -eq 0 ]; then
  # Count entries ignoring .git
  ENTRIES=$(find "$TARGET_ABS" -mindepth 1 -maxdepth 1 -not -name '.git' | wc -l)
  if [ "$ENTRIES" -gt 0 ]; then
    echo "ERROR: $TARGET_ABS is not empty. Pass --force to scaffold into existing dir (skips files that already exist)." >&2
    exit 1
  fi
fi

# ── Write file helper (skip if exists) ───────────────────────────────────────
write_file() {
  local dest="$1"
  local src="$2"
  if [ -f "$dest" ]; then
    echo "SKIP   $dest (exists)"
    return 0
  fi
  cp "$src" "$dest"
  echo "WRITE  $dest"
}

# ── Render template with REPO_NAME substitution ──────────────────────────────
render_template() {
  local dest="$1"
  local src="$2"
  if [ -f "$dest" ]; then
    echo "SKIP   $dest (exists)"
    return 0
  fi
  sed "s|{{REPO_NAME}}|${REPO_NAME}|g" "$src" > "$dest"
  echo "WRITE  $dest"
}

# ── 1. Directories ───────────────────────────────────────────────────────────
mkdir -p "$TARGET_ABS/workflows" \
         "$TARGET_ABS/schemas/nodes" \
         "$TARGET_ABS/data" \
         "$TARGET_ABS/docs"
echo "MKDIR  workflows/ schemas/nodes/ data/ docs/"

# Gitkeeps so empty dirs survive
[ -f "$TARGET_ABS/workflows/.gitkeep" ] || touch "$TARGET_ABS/workflows/.gitkeep"
[ -f "$TARGET_ABS/schemas/nodes/.gitkeep" ] || touch "$TARGET_ABS/schemas/nodes/.gitkeep"
[ -f "$TARGET_ABS/data/.gitkeep" ] || touch "$TARGET_ABS/data/.gitkeep"

# ── 2. Template files ────────────────────────────────────────────────────────
render_template "$TARGET_ABS/CLAUDE.md"      "$TEMPLATES_DIR/CLAUDE.md"
render_template "$TARGET_ABS/README.md"      "$TEMPLATES_DIR/README.md"
write_file      "$TARGET_ABS/.gitignore"     "$TEMPLATES_DIR/gitignore"
write_file      "$TARGET_ABS/.mcp.json"      "$TEMPLATES_DIR/mcp.json"
write_file      "$TARGET_ABS/.env.example"   "$TEMPLATES_DIR/env.example"
write_file      "$TARGET_ABS/n8nac-config.json.example" "$TEMPLATES_DIR/n8nac-config.json.example"

# ── 3. git init ──────────────────────────────────────────────────────────────
if [ "$NO_GIT" -eq 0 ]; then
  if [ -d "$TARGET_ABS/.git" ]; then
    echo "SKIP   git init (.git exists)"
  else
    (cd "$TARGET_ABS" && git init --initial-branch=main >/dev/null 2>&1 || git init >/dev/null)
    echo "GIT    initialized"
  fi
fi

echo ""
echo "=== Scaffold complete ==="
echo ""
echo "Next steps:"
echo "  1. cd $TARGET_ABS"
echo "  2. cp .env.example .env             # fill in N8N_API_URL + N8N_API_KEY"
echo "  3. npx n8nac init                   # creates n8nac-config.json (interactive)"
echo "     OR: npx n8nac init-auth --yes && npx n8nac init-project --yes"
echo "  4. In Claude Code: /n8n-autopilot:pull-schemas"
echo "  5. Verify: bash \"\$(claude plugin path n8n-autopilot)/scripts/setup-check.sh\""
echo ""
