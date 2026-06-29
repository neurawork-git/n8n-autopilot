# n8n Workflow Development — n8n-autopilot Plugin

This repo uses the **n8n-autopilot plugin** for Claude Code.
Workflows are TypeScript (Decorator format). Never write n8n JSON by hand.

> **Reference n8nac version: 2.3.6** (minimum 2.3.0). All setup/credential flows below target the v4-native environment-centric config model. Single source of truth: `REFERENCE_N8NAC_VERSION` in `scripts/setup-check.sh`. Bump: update the constant, sync README badges + `plugin.json`, add CHANGELOG entry.

## Knowledge skills — read BEFORE inventing CLI surface

| Skill | When to read |
|---|---|
| [`n8nac-cheatsheet`](skills/n8nac-cheatsheet/SKILL.md) | Default first stop. "Which command for X?" — curated table, 60+ operations across workspace, env, workflows, executions, credentials, recipes, schemas. |
| [`n8nac-reference`](skills/n8nac-reference/SKILL.md) | Raw `n8nac --help` tree, 61 command/subcommand blocks. Read when the cheat-sheet does not cover a request. Source of truth for "does this command exist?" — if not in `reference.md`, it does not exist. |
| [`n8n-architect`](https://github.com/EtienneLescot/n8n-as-code) (companion plugin) | Schema-First Research, workflow authoring rules, AI/LangChain patterns, Common Mistakes. Owned by Etienne's `n8n-as-code` plugin. |

**Rule:** before running `npx n8nac <cmd> --help` interactively, `grep` the cheat-sheet, then `grep` the reference file. Only fall back to live `--help` if both fail — and treat that as a sign to regenerate the reference (`bash scripts/dump-n8nac-help.sh > skills/n8nac-reference/reference.md`).

## Cheat-Sheet — User asks X → run Y

**Use these BEFORE inventing flags or grepping `--help`.** If the user's intent matches a row, run the linked skill/command verbatim. If no row matches, ask the user — do not guess.

| User intent | Exact command |
|---|---|
| "find credential <name>" / "which cred is X" / "list Dropbox creds in this project" | `/n8n-autopilot:find-credential <pattern>` (project-scoped; add `--type <credType>` or `--project all`) |
| "list n8n projects" / "which projects exist" | `/n8n-autopilot:find-project` |
| "switch workspace to project X" | verify env target via `npx n8nac env list --json`, then `npx n8nac env update <env> --project-name "<X>"` then `/n8n-autopilot:check-mcps` |
| "show active project / instance binding" | `npx n8nac workspace status --json` |
| "build a workflow that does X" | `/n8n-autopilot:build-workflow "<description>"` (prose pipeline) |
| "build/edit with hard-enforced gates" (experimental) | `/n8n-autopilot:build-workflow-v2 "<description>"` — JS-orchestrated, gate-checks as control flow |
| "build a whole multi-workflow STACK" / "orchestrator + sub-workflows from one use case" (experimental) | `/n8n-autopilot:build-stack-v2 "<end-to-end use case>"` (or `extend "<stack>" "<change>"`) — decompose → handover contracts + mermaid → bottom-up build via build-workflow-v2 |
| "help me plan an n8n workflow" / "automate X but don't know how" / rough idea | `/n8n-autopilot:stack-intake "<one-line idea>"` — guided interview → writes a PRP for build-stack-v2 |
| "deploy <file>.workflow.ts" | `/n8n-autopilot:deploy <file>.workflow.ts` |
| "pull every remote-only workflow / fix mirror drift" | `/n8n-autopilot:mirror-sync` |
| "which env/instance is this session on" / "pin session to env X" / "why was my env command blocked" | `/n8n-autopilot:session-env` (explains model + reports session-vs-global). Pin per-session via `.claude/settings.json` `env` block `N8NAC_ENVIRONMENT=<env>` (or `export`/`--env`) — **never `env use`** (see Gates below) |
| "fix stale credential IDs in workflows" | `/n8n-autopilot:sync-credentials --fix-workflows` (project-scoped) |
| "regenerate inventory / list of nodes" | `/n8n-autopilot:inventory` |
| "data table CRUD" (create/seed/list/drop tables in n8n) | `/n8n-autopilot:data-tables` |
| "give feedback" / "report friction" | `/n8n-autopilot:feedback` (interview); `/n8n-autopilot:feedback sync` pushes centrally (consent-gated) |
| "pull schemas" / "update node schemas" | `/n8n-autopilot:pull-schemas` |
| "check setup / MCP / instance health" | `/n8n-autopilot:check-mcps` |
| "find a workflow by name" | `npx n8nac find <query> --json` (`--remote` for instance-side; default = local+remote) |
| "test schedule/manual/error-trigger workflow" / "non-HTTP test" | `/n8n-autopilot:test-manual <workflowId>` (resolves UI URL → waits for execution-id → inspects run) |
| "show executions of workflow <id>" | `npx n8nac execution list --workflow <id>` |
| "inspect a specific execution" | `npx n8nac execution get <executionId> --include-data` |
| "resolve workflow URL for UI" | `npx n8nac workflow present <id> --json` (never string-concat `<host>/workflow/<id>`) |
| "pull workflow from instance" | `npx n8nac pull <id>` |
| "refresh remote state without overwriting local" | `npx n8nac fetch <id>` |

**Multi-project rule:** every credential/workflow operation runs in the **workspace-pinned project's scope**. Verify the pin via `npx n8nac workspace status --json` before any cred-touching operation. If "is this the right project?" is uncertain, run `/n8n-autopilot:find-project` first.

## Hook Gates (enforced by `PreToolUse` hooks)

Two hooks protect against drift and cross-session env clobbering. Operational rules only here — full mechanism, resolution paths, and bypass env-vars in **[docs/troubleshooting/gates.md](docs/troubleshooting/gates.md)**.

- **Push-Gate** (`scripts/push-gate.sh`) — blocks `push` when remote drifted (`CONFLICT`/`MODIFIED_BOTH`/`DIVERGED`/`REMOTE_ONLY`) and always blocks `resolve --mode keep-current|keep-local|local-wins`. Auto-fetches before judging. Recovery: `pull` → re-edit → `push --verify`. New workflows (no `id:`) are never blocked.
- **Env-Gate** (`scripts/enforce-env.sh`) — a session works in exactly ONE n8n env. Fail-closed BLOCKS any instance-touching command with no explicit env. Resolve it via `export N8NAC_ENVIRONMENT=<env>` (normal per-session pin), inline `N8NAC_ENVIRONMENT=<env> npx n8nac …`, or `--env <env>`. **Never `env use`/`env pin`** — they mutate the machine-GLOBAL active env (shared across sessions) and are blocked by the clobber-guard. Gotcha: `workspace status` is env-blind; use `env status` / `env list --json` for session-aware resolution. Full model + isolation test → [`session-env` skill](skills/session-env/SKILL.md).

## Setup

**Brand-new repo? One command:**
→ `/n8n-autopilot:init-repo [target-dir]` — scaffolds dir layout + CLAUDE.md/README/.gitignore/.mcp.json/.env.example, runs the v2.3 setup flow (`env add` + `env auth set` + `env use`), pulls schemas, verifies.

**Manual (step-by-step):**
1. Install both plugins (n8n-autopilot + Etienne's companion):
   ```bash
   claude plugin marketplace add neurawork-git/n8n-autopilot
   claude plugin install n8n-autopilot@n8n-autopilot

   claude plugin marketplace add EtienneLescot/n8n-as-code
   claude plugin install n8n-as-code@n8nac-marketplace
   ```
   The companion (Etienne) provides the `n8n-architect` skill (schema-research, authoring rules, AI/LangChain rules). n8n-autopilot does workflow lifecycle orchestration (init-repo, build-workflow pipeline, deploy, sync-credentials, inventory, data-tables).
2. Add and activate the environment (n8nac >= 2.3 stores config in user home, NOT the repo):
   ```bash
   npx n8nac env add Prod --base-url "$N8N_API_URL" --workflows-path workflows
   printf '%s' "$N8N_API_KEY" | npx n8nac env auth set Prod --api-key-stdin
   npx n8nac env use Prod
   # Optional, for multi-project instances:
   npx n8nac env update Prod --project-name Personal
   ```
3. `/n8n-autopilot:pull-schemas` — populate `schemas/nodes/` (gitignored, instance-specific)
4. Verify: `/n8n-autopilot:check-mcps` (also runs via SessionStart hook; expects workspace status `bound`)

**Stray in-repo `./n8nac-config.json`?** The `workspace migrate` / `migrate-v1` commands no longer exist — workspace storage is v4-native (config in `~/n8nac-config.json` + `~/.n8n-manager/`). If a legacy in-repo config file exists, **delete it manually** — there is no migration command.

## Auto-Reactions on SessionStart

SessionStart hooks emit `AUTOPILOT_ACTION_REQUIRED: <slash-command>` lines when state is stale and an automated fix exists. When you see such a line, **run that exact slash-command immediately, without asking first** — these signals only fire when the action is safe and idempotent.

| Signal source | Hook? | Trigger | Auto-action |
|---|---|---|---|
| `check-schema-versions.sh` | direct (SessionStart) | Cached schema older than latest npm version | `/n8n-autopilot:pull-schemas --community-only --packages <list>` |
| `check-installed-nodes.sh` | indirect (via `setup-check.sh` §7) | Community node on instance, no cached schema | `/n8n-autopilot:pull-schemas --community-only --packages <list>` |
| `check-credential-freshness.sh` | direct (SessionStart) | Workflow references credential ID not on instance | `/n8n-autopilot:sync-credentials --fix-workflows` |
| `check-mirror-drift.sh` | direct (SessionStart) | Remote workflow exists with no local file | `/n8n-autopilot:mirror-sync` |

Hard rule: parse the literal slash-command after `AUTOPILOT_ACTION_REQUIRED:` and execute it. Do not paraphrase, do not skip the `--packages` list, do not bundle multiple signals into one call.

Signals NOT auto-triggered (informational only):
- `check-inventory-freshness.sh` (`INFO:` — surface to user; inventory regeneration is expensive).
- `check-feedback-pending.sh` (`INFO:` — unsynced feedback records exist; offer `/n8n-autopilot:feedback`, do NOT auto-run — consent needed).
- `check-workspace-migration.sh` — warns on a stray in-repo `./n8nac-config.json`. `workspace migrate`/`migrate-v1` no longer exist; ask the user to **delete the in-repo file manually**.

## Entry Point & Deploy

- Create/build/scaffold a workflow → `/n8n-autopilot:build-workflow "description"` (full pipeline incl. deploy). **NEVER write workflow code directly** — Phase 0 research via n8nac is mandatory.
- Deploy → `/n8n-autopilot:deploy <workflow-name>.workflow.ts`

## Tool Boundaries (non-discoverable rules)

Full CLI catalog + manual detours: **[docs/rules/tool-boundaries.md](docs/rules/tool-boundaries.md)**. Most commands are also in the [`n8nac-cheatsheet`](skills/n8nac-cheatsheet/SKILL.md) / [`n8nac-reference`](skills/n8nac-reference/SKILL.md) skills — grep those first. The rules below are NOT discoverable from `--help` and must be honoured:

- **n8nac is PRIMARY** for everything: node research (n8nac MCP tools), `skills validate`, `push --verify`, `test`, executions, credentials.
- **Never call the n8n REST API directly** (curl, fetch, HTTP Request node) — **exception:** `/api/v1/data-tables`, managed only via the `/n8n-autopilot:data-tables` skill (n8nac has no `datatable` subcommand; the PreToolUse curl-block carves out this one path).
- **Never delete workflows** without explicit user confirmation.
- **Never write workflow JSON by hand** — always Decorator-TS format.
- **Archived workflows are read-only** — `push` is rejected. No code-fix loop; unarchive (n8n UI) or recreate first. (`list`/`find` default-exclude archived; `--include-archived` / `--only-archived` to see them.)
- **Never string-concat workflow URLs** — resolve via `npx n8nac workflow present <id> --json`.
- **Removed commands — never use:** `init` / `init-auth` / `init-project` (pre-2.2; use `npx n8nac setup --mode …`) and `workspace migrate` / `migrate-v1` (delete stray config manually).
- **`mcpTrigger` workflows need a manual Publish in the n8n UI** after every push — n8nac cannot publish, the MCP endpoint stays on the old draft. Steps in [docs/rules/tool-boundaries.md](docs/rules/tool-boundaries.md).
- **Non-HTTP triggers** (`schedule`/`manual`/`errorTrigger`) cannot be fired by `n8nac test` — use `/n8n-autopilot:test-manual <id>` (manual UI-execute → execution-id → inspect).
- **Feedback** pushes ONE labelled GitHub issue to `neurawork-git/n8n-autopilot-internal`, consent-gated, with a deterministic PII gate (`scripts/redact-check.js`). No hook ever pushes.
- **Design quality** is enforced by the `workflow-reviewer` agent (15 points: native-first, no silent failures, memory/large-data, descriptions, no overlapping positions) plus auto-activated pattern skills (`n8n-orchestration-patterns`, `n8n-structured-extraction`, `data-tables`).
