---
name: init-repo
description: Bootstrap a new n8n workflow repo from scratch. Scaffolds directory structure, writes plugin-compatible CLAUDE.md/README/.gitignore/.mcp.json/.env.example, runs `n8nac init`, pulls node schemas, and verifies setup. Use when starting a new customer/project n8n repo.
argument-hint: "[target-dir] [--here] [--force] [--skip-schemas]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(bash:*), Bash(npx:*), Bash(git:*), Bash(cp:*), Bash(test:*), Bash(mkdir:*), Bash(ls:*)
---

# Init n8n Workflow Repo

Bootstrap a brand-new n8n workflow repo so the user can immediately start with `/n8n-autopilot:build-workflow`.

This skill is the **single entrypoint** for new-repo setup. Replaces the manual 6-step CLAUDE.md checklist.

## Arguments

| Arg | Meaning |
|-----|---------|
| `<target-dir>` | Path where the repo lives. Defaults to current dir. If missing, will be created. |
| `--here` | Force scaffold into current dir even if non-empty (alias for `--force` with target `.`). |
| `--force` | Scaffold into non-empty target; existing files are NOT overwritten. |
| `--skip-schemas` | Skip the `pull-schemas` step (faster, run later manually). |

## Pre-flight

Before doing anything:

1. **Detect plugin self-bootstrap.** Refuse if target dir contains `.claude-plugin/plugin.json` with `"name": "n8n-autopilot"` — that's the plugin source, not a consumer repo.
2. **Detect already-bootstrapped.** If `n8nac-config.json` already exists in target → abort with clear message ("delete it manually to re-init").
3. **Check tools.** `npx --version` and `git --version` must work. Fail loud if missing.

## Steps

### 1. Scaffold files

Run the deterministic scaffold script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/init-repo/scripts/init-repo.sh" "<target-dir>" [--force] [--no-git]
```

This creates `workflows/`, `schemas/nodes/`, `data/`, `docs/` and writes templated `CLAUDE.md`, `README.md`, `.gitignore`, `.mcp.json`, `.env.example`, `n8nac-config.json.example`, runs `git init`.

**Output to user:** Summarize what was written / skipped.

### 2. Collect connection info

Ask the user — one prompt, three answers — for:

- **n8n host URL** (e.g. `https://n8n.customer.example.com`)
- **n8n API key** (from n8n UI → Settings → API)
- **Project name** in n8n (optional — if blank, n8nac defaults to Personal)

Do NOT write these to a committed file. Plan:
- Host + API key → `.env` and `n8nac-config.json` (gitignored)
- Project ID picked interactively via `npx n8nac init-project`

If user can't provide right now: skip steps 3–5, print remaining manual commands, and stop. Don't fail.

### 3. Write `.env`

In the target dir, copy `.env.example` → `.env` and substitute `N8N_API_URL` and `N8N_API_KEY` with what the user gave.

```bash
cd <target-dir>
cp .env.example .env
# then Edit tool: replace N8N_API_URL=... and N8N_API_KEY= line
```

Use the Edit tool, NOT `sed -i` — Windows safety.

### 4. Init n8nac

```bash
cd <target-dir>
npx --yes n8nac init-auth --yes --host "<host>" --api-key "<key>"
npx --yes n8nac init-project --yes
```

If `init-project` fails with multiple-project ambiguity, fall back to interactive:

```bash
npx n8nac init-project
```

and let the user pick. Verify success:

```bash
test -f n8nac-config.json && echo OK || echo MISSING
```

### 5. Pull schemas

Unless `--skip-schemas`:

→ Invoke skill `/n8n-autopilot:pull-schemas` (run it inline — same session).

Schemas land in `schemas/nodes/`, index in `schemas/_index.json`. Both gitignored.

### 6. Verify

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-check.sh"
```

Expect "All checks passed". If errors → diagnose and report, don't silently swallow.

### 7. Final message

Print to the user:

```
✅ Repo ready: <target-dir>

Try it now:
  /n8n-autopilot:build-workflow "your idea here"

Or deploy an existing workflow:
  /n8n-autopilot:deploy workflows/foo.workflow.ts

First commit:
  cd <target-dir>
  git add .
  git commit -m "chore: bootstrap n8n-autopilot repo"
```

## Failure handling

- **Tool missing (npx/git)**: stop, tell user how to install, don't continue.
- **n8nac init fails**: print exact stderr, leave repo half-bootstrapped, tell user what to fix and how to rerun (just the failing step, not the whole skill).
- **pull-schemas fails**: continue anyway — schemas are nice-to-have, user can run `/n8n-autopilot:pull-schemas` later.
- **setup-check fails**: report errors, do NOT delete anything, give user the rerun command.

Never delete files the user might have written between steps.

## Notes

- Skill is idempotent at the file-scaffold level (Step 1) — never overwrites existing files.
- Steps 3–6 will re-run cleanly on a partially bootstrapped repo.
- Templates live in `${CLAUDE_PLUGIN_ROOT}/skills/init-repo/assets/templates/` (colocated with the skill per skill-creator convention). If user wants to customize them per-customer, they can fork the plugin or override post-init.
- For multi-environment setups (one repo, many n8n tenants), run `npx n8nac env add <name>` per environment after this skill, then `npx n8nac env use <name>` to switch.
