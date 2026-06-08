---
name: init-repo
description: Bootstrap a new n8n workflow repo from scratch. Scaffolds directory structure, writes plugin-compatible CLAUDE.md/README/.gitignore/.env.example, runs the n8nac >= 2.3 setup flow (`env add` + `env auth set` + `env use`), pulls node schemas, and verifies setup. Use when starting a new customer/project n8n repo.
argument-hint: "[target-dir] [--here] [--force] [--skip-schemas]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(bash:*), Bash(npx:*), Bash(git:*), Bash(cp:*), Bash(test:*), Bash(mkdir:*), Bash(ls:*)
---

# Init n8n Workflow Repo

Bootstrap a brand-new n8n workflow repo so the user can immediately start with `/n8n-autopilot:build-workflow`.

This skill is the **single entrypoint** for new-repo setup. Replaces the manual checklist.

> **Reference n8nac version: 2.3.6** (minimum 2.3.0). The setup flow below targets the environment-centric model: environments are created with `n8nac env add`, authenticated with `n8nac env auth set`, and activated with `n8nac env use`. Workspace/instance config lives in user home (`~/n8nac-config.json` + `~/.n8n-manager/`), not in the workspace root. The old `workspace migrate-v1` command no longer exists — stray in-repo `n8nac-config.json` files must be deleted manually.

## Arguments

| Arg | Meaning |
|-----|---------|
| `<target-dir>` | Path where the repo lives. Defaults to current dir. If missing, will be created. |
| `--here` | Force scaffold into current dir even if non-empty (alias for `--force` with target `.`). |
| `--force` | Scaffold into non-empty target; existing files are NOT overwritten. |
| `--skip-schemas` | Skip the `pull-schemas` step (faster, run later manually). |

## Pre-flight

1. **Detect plugin self-bootstrap.** Refuse if target dir contains `.claude-plugin/plugin.json` with `"name": "n8n-autopilot"` — that's the plugin source, not a consumer repo.
2. **Check tools.** `npx --version` and `git --version` must work. Fail loud if missing.
3. **Detect legacy in-repo config.** If `<target>/n8nac-config.json` exists (legacy workspace-local config from n8nac < 2.2), warn the user that `workspace migrate-v1` no longer exists and the file must be **deleted manually** — config now lives in user home (`~/n8nac-config.json` + `~/.n8n-manager/`). Do not delete the file automatically.

## Steps

### 1. Scaffold files

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/init-repo/scripts/init-repo.sh" "<target-dir>" [--force] [--no-git]
```

Creates `workflows/`, `schemas/nodes/`, `data/`, `docs/` and writes templated `CLAUDE.md`, `README.md`, `.gitignore`, `.env.example`, runs `git init`. Idempotent. No `.mcp.json` is scaffolded — n8n-autopilot 4.x is CLI-only.

It then runs `ensure-claude-section.js` to **anchor the n8n-autopilot section into `CLAUDE.md`**
(idempotent): a brand-new repo already has the full template (the script SKIPs, no duplicate); an
**existing repo with its own CLAUDE.md** gets the marked section
(`<!-- n8n-autopilot:start -->`…`<!-- n8n-autopilot:end -->`) appended, and re-runs only refresh that
block — repo-specific content outside the markers is never touched.

**Output to user:** Summarize what was written / skipped / appended.

> **Anchor into an existing repo without full scaffolding:** to only add/refresh the autopilot section
> in a repo that already has its own CLAUDE.md (e.g. an established customer repo), run just:
> ```bash
> node "${CLAUDE_PLUGIN_ROOT}/skills/init-repo/scripts/ensure-claude-section.js" --workspace .
> ```

### 2. Collect connection info

Ask the user — one prompt, two answers — for:

- **n8n host URL** (e.g. `https://n8n.customer.example.com`)
- **n8n API key** (from n8n UI → Settings → API)

Project assignment is decided in step 5 once `setup` has surfaced available projects.

If user can't provide right now: skip steps 3–6, print the remaining manual commands (see `init-repo.sh` "Next steps" tail), and stop. Don't fail.

### 3. Write `.env`

In the target dir, copy `.env.example` → `.env` and substitute `N8N_API_URL` and `N8N_API_KEY` with what the user gave.

Use the Edit tool, NOT `sed -i` — Windows safety.

### 4. Create and authenticate the environment (n8nac 2.3 flow)

```bash
cd <target-dir>
# Register the environment (name, instance URL, workflows folder, optional project)
npx n8nac env add <env-name> \
  --base-url "<host>" \
  --workflows-path workflows \
  [--project-name "<project>"]   # omit for single-project instances

# Store the API key (via stdin — never echoed to shell history)
printf "%s" "$N8N_API_KEY" | npx n8nac env auth set <env-name> --api-key-stdin
```

`<env-name>` is a short label for this environment (e.g. `Prod`, `CustomerX`). Use the same name throughout the session.

### 5. Activate the environment + verify

```bash
# Activate (all subsequent n8nac instance commands target this env)
npx n8nac env use <env-name>

# Verify effective config
npx n8nac workspace status --json
```

Status `ready` / `active` / `ok` = good.

If the user's n8n has multiple projects and the user did not specify one at `env add` time, update the environment:

```bash
npx n8nac env update <env-name> --project-name "<project>"
```

### 6. Pull schemas

Unless `--skip-schemas`:

→ Invoke skill `/n8n-autopilot:pull-schemas` (run it inline — same session).

Schemas land in `schemas/nodes/`, index in `schemas/_index.json`. Both gitignored.

### 6.5 Mirror remote workflows

Pull every workflow that already exists in the bound project so the repo starts as a **complete local mirror** of the instance. This is what makes `/n8n-autopilot:build-workflow-v2`'s local-first edit flow valid, and what the SessionStart drift probe (`check-mirror-drift.sh`) keeps honest afterwards.

→ Invoke skill `/n8n-autopilot:mirror-sync` (run it inline — same session). It discovers remote-only workflows and fan-out-pulls them.

A brand-new/empty project pulls nothing (mirror already complete) — that's fine. Failures are non-fatal: report them, the user can re-run `/n8n-autopilot:mirror-sync` or `npx n8nac pull <id>` manually.

### 7. Verify

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-check.sh"
```

Expect "All checks passed". If errors → diagnose and report, don't silently swallow.

### 8. Final message

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
- **`npx n8nac env add` fails**: print exact stderr, leave repo half-bootstrapped, tell user what to fix and how to rerun (just the failing step, not the whole skill).
- **`npx n8nac env auth set` fails**: most likely cause is a wrong env name or an invalid API key — verify with `npx n8nac env list` and re-run.
- **pull-schemas fails**: continue anyway — schemas are nice-to-have, user can run `/n8n-autopilot:pull-schemas` later.
- **setup-check fails**: report errors, do NOT delete anything, give user the rerun command.

Never delete files the user might have written between steps.

## Notes

- Skill is idempotent at the file-scaffold level (Step 1) — never overwrites existing files. The
  CLAUDE.md autopilot section is marker-delimited and refreshed in place (no duplication); content
  outside the markers is preserved.
- Steps 3–7 will re-run cleanly on a partially bootstrapped repo.
- Templates live in `${CLAUDE_PLUGIN_ROOT}/skills/init-repo/assets/templates/` (colocated with the skill per skill-creator convention).
- For multi-environment setups (one repo, many n8n tenants), run `npx n8nac env add <name>` per environment and `npx n8nac env use <name>` to switch.
- The legacy `init` / `init-auth` / `init-project` commands were removed in n8nac 2.2 — do NOT use them.
- The `workspace pin-instance`, `workspace set-sync-folder`, `workspace set-project`, `workspace migrate`, and `workspace migrate-v1` commands were removed in n8nac 2.3 — do NOT use them.
