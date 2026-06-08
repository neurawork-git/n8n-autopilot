---
name: n8nac-reference
description: Authoritative reference for every `n8nac` CLI command, subcommand, and flag (n8nac 2.3.6). Use this BEFORE running `--help` interactively, BEFORE guessing flags, and BEFORE inventing a subcommand. If a command does not appear in this file, it does not exist — research stops, do not invent CLI surface. Covers workspace, env, setup, credentials, credential, workflow, execution, skills, list/find/pull/push/promote/verify/test/test-plan/fetch/resolve/convert, plus subcommand-level help.
allowed-tools: Read, Grep, Glob, Bash(grep:*)
---

# n8nac CLI — Authoritative Reference

The full `n8nac --help` tree is captured in [`reference.md`](reference.md) (auto-generated, 61 command/subcommand blocks across 24 top-level groups). Read it whenever you need to:

- Know if a command exists (rule: **not in the file → does not exist**, do not invent it).
- Look up exact flag names and short/long forms.
- Understand the argument order for a subcommand.

## Quick navigation

Search the reference file with `grep`:

```bash
# Find a parent command
grep "^## \`n8nac credential" "$CLAUDE_PLUGIN_ROOT/skills/n8nac-reference/reference.md"

# Find a specific subcommand
grep -n "^### \`n8nac credential list\`" "$CLAUDE_PLUGIN_ROOT/skills/n8nac-reference/reference.md"

# Pull the full help block for one subcommand (next 30 lines after the header)
awk '/^### `n8nac workflow credential-required`/{flag=1;n=0} flag{print;n++; if(n>30)exit}' \
  "$CLAUDE_PLUGIN_ROOT/skills/n8nac-reference/reference.md"
```

## Subcommand index (alphabetical by parent)

| Parent | Subcommands |
|---|---|
| (root) | `find`, `pull`, `push`, `promote`, `verify`, `test`, `test-plan`, `fetch`, `resolve`, `convert`, `convert-batch`, `list`, `mcp`, `setup`, `setup-modes`, `update-ai` |
| `credential` | `create`, `delete`, `get`, `list`, `schema` |
| `credentials` (readiness/recipes) | `delete`, `ensure`, `inventory`, `recipes`, `starter-kit`, `starter-kits`, `test` |
| `env` | `add`, `auth`, `list`, `pin`, `remove`, `status`, `update` |
| `execution` | `get`, `list` |
| `skills` | `docs`, `examples`, `guides`, `list`, `mcp`, `node-info`, `node-schema`, `related`, `search`, `update-ai`, `validate` |
| `workflow` | `activate`, `credential-required`, `deactivate`, `present` |
| `workspace` | `status` (alias `get`) — **read-only** since 2.3; all mutation moved to `env` |
| `telemetry` | (no subcommands — flags only) |

`credentials` (plural) and `credential` (singular) are **different** parent groups. Plural is for recipe / readiness / inventory management; singular is for direct create/list/get/delete/schema operations on the active instance. Mixing them is a common source of "command not found" errors.

## When to read the full file vs. a single block

- **Single subcommand lookup** (90% of cases): use `grep` / `awk` snippet above to pull just the block you need. ~30 lines.
- **Full file read** (rare): only when you need an overview of a parent group's surface (e.g. "what does the `env` group do as a whole?").

## How to regenerate

```bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/dump-n8nac-help.sh" > "$CLAUDE_PLUGIN_ROOT/skills/n8nac-reference/reference.md"
```

Re-run whenever the `setup-check.sh` `REFERENCE_N8NAC_VERSION` constant is bumped. The script captures the version from `npx n8nac --version` and stamps it at the top + bottom of the file.

## Companion: high-level patterns

For the curated "which command for which user intent" mapping (cheat-sheet form), see **[`n8nac-cheatsheet`](../n8nac-cheatsheet/SKILL.md)** and the **Cheat-Sheet** section in `CLAUDE.md`. This skill is the raw-help fallback when the cheatsheet does not have a row for the user's request.
