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
#
# n8nac >= 2.3 note: environments are the config unit (not workspace mutations).
# After this script finishes, bind the repo to an n8n instance via:
#   npx n8nac env add <name> --base-url <url> --workflows-path workflows
#   printf '%s' "$N8N_API_KEY" | npx n8nac env auth set <name> --api-key-stdin
#   npx n8nac env use <name>

set -euo pipefail

# ── Resolve skill root ───────────────────────────────────────────────────────
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
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
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

# ── Refuse non-empty dir unless --force ──────────────────────────────────────
# (We no longer refuse on n8nac-config.json — in n8nac >= 2.3 that file lives
# in user home, not the workspace. Workspace state is detected via
# `npx n8nac workspace status` after scaffolding.)
if [ "$FORCE" -eq 0 ]; then
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
write_file      "$TARGET_ABS/.env.example"   "$TEMPLATES_DIR/env.example"

# ── 2b. Ensure the n8n-autopilot section is anchored in CLAUDE.md (idempotent) ─
# New repo → full template already written (sentinel) → script SKIPs (no dupe).
# Existing/foreign CLAUDE.md → script appends/updates the marked section.
node "$SKILL_ROOT/scripts/ensure-claude-section.js" --workspace "$TARGET_ABS" \
  || echo "WARN   ensure-claude-section failed (non-fatal) — CLAUDE.md not modified"

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
echo "Next steps (n8nac >= 2.3 setup flow):"
echo "  1. cd $TARGET_ABS"
echo "  2. cp .env.example .env             # fill in N8N_API_URL + N8N_API_KEY"
echo "  3. Register and authenticate the environment (ENV_NAME = short label, e.g. Prod):"
echo "       npx n8nac env add \"\$ENV_NAME\" --base-url \"\$N8N_API_URL\" --workflows-path workflows"
echo "       printf '%s' \"\$N8N_API_KEY\" | npx n8nac env auth set \"\$ENV_NAME\" --api-key-stdin"
echo "     Multi-project instance? Add: --project-name \"<Project>\""
echo "  4. Activate the environment:"
echo "       npx n8nac env use \"\$ENV_NAME\""
echo "  5. In Claude Code: /n8n-autopilot:pull-schemas"
echo "  6. Verify: open Claude Code in the new repo (SessionStart hook runs setup-check)"
echo "     Or invoke explicitly: /n8n-autopilot:check-mcps"
echo ""
echo "Legacy in-repo n8nac-config.json found?"
echo "  The 'workspace migrate-v1' command no longer exists in n8nac >= 2.3."
echo "  Delete the file manually — config now lives in user home (~/n8nac-config.json + ~/.n8n-manager/)."
echo ""
