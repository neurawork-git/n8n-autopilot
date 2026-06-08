#!/usr/bin/env bash
# dump-n8nac-help.sh — Walk the n8nac CLI help tree and emit a single Markdown
# reference. Used as a build step for the `n8nac-reference` knowledge skill.
#
# Output: stdout (Markdown). Pipe into the skill's reference file.
#
# Strategy:
#   - Explicit allowlist of n8nac parent commands (avoids parsing wrap-around
#     description lines as subcommand names).
#   - For each parent: capture `--help` AND probe known subcommand names.
#   - Two levels deep is enough — n8nac never nests further.
#
# To regenerate after an n8nac upgrade:
#   bash scripts/dump-n8nac-help.sh > skills/n8nac-reference/reference.md

set -u

N8NAC_VERSION=$(npx --yes n8nac --version 2>/dev/null | head -1)
ROOT_HELP=$(npx --yes n8nac --help 2>&1 || true)

# Strict subcommand parser: only lines starting with exactly two spaces,
# followed by a lowercase word with no further leading spaces. Excludes
# description-continuation lines (which always start with many more spaces).
list_subs() {
  local parent="$1"
  # Strict: only "  <word>" or "  <word>|<alias>" lines starting at exactly
  # column 3 (two leading spaces, then a lowercase letter). Description
  # continuation lines are at column ~37+ — never match.
  npx --yes n8nac $parent --help 2>&1 \
    | awk '
        /^Commands:/   { in_cmds=1; next }
        in_cmds && /^$/ { in_cmds=0 }
        in_cmds && /^  [a-z]/ {
          line=$0
          sub(/^  /, "", line)
          # First word, stripping pipe-aliases, brackets, angle brackets, spaces
          word=line
          gsub(/[|<[ ].*/, "", word)
          if (word ~ /^[a-z][a-z0-9-]*$/ && word != "help") print word
        }
      ' \
    | sort -u
}

emit_block() {
  local cmd="$1"
  echo "### \`$cmd\`"
  echo ''
  echo '```'
  npx --yes $cmd --help 2>&1 || true
  echo '```'
  echo ''
}

# Hard-coded parent allowlist (from n8nac 2.3.6 root --help).
TOP_CMDS=(
  telemetry
  workspace
  env
  setup
  setup-modes
  credentials
  list
  find
  pull
  push
  promote
  verify
  test
  test-plan
  fetch
  resolve
  convert
  convert-batch
  mcp
  workflow
  execution
  credential
  skills
  update-ai
)

cat <<EOF
# n8nac CLI Reference — Generated

Generated automatically from \`n8nac --help\` recursion. n8nac version: **${N8NAC_VERSION}**.

This file is the source of truth for what subcommands and flags exist. If a command appears here, it exists. If it does not appear here, **it does not exist** — do not invent it.

To regenerate after an n8nac upgrade:

\`\`\`bash
bash scripts/dump-n8nac-help.sh > skills/n8nac-reference/reference.md
\`\`\`

---

## Root

\`\`\`
${ROOT_HELP}
\`\`\`

EOF

for cmd in "${TOP_CMDS[@]}"; do
  echo "---"
  echo ''
  echo "## \`n8nac $cmd\`"
  echo ''
  emit_block "n8nac $cmd"

  # Only commands known to have subcommands
  case "$cmd" in
    workspace|env|credentials|workflow|execution|credential|skills)
      SUBS=$(list_subs "$cmd")
      for sub in $SUBS; do
        emit_block "n8nac $cmd $sub"
      done
      ;;
  esac
done

echo "---"
echo ''
echo "_End of generated reference. ${N8NAC_VERSION}_"
