# n8n Workflow Development — n8n-autopilot Plugin

This repo uses the **n8n-autopilot plugin** for Claude Code.
Workflows are TypeScript (Decorator format). **Never write n8n JSON by hand.**

> **Reference n8nac version: 2.7.0** (minimum 2.3.0), v4-native environment-centric config model.
> SSOT = `REFERENCE_N8NAC_VERSION` in `scripts/setup-check.sh`. Setup + bump procedure: [docs/rules/setup.md](docs/rules/setup.md).

## Knowledge skills — read BEFORE inventing CLI surface

| Skill | When to read |
|---|---|
| [`n8nac-cheatsheet`](skills/n8nac-cheatsheet/SKILL.md) | Default first stop. "Which command for X?" — curated table, 60+ common operations across workspace, env, workflows, executions, credentials, recipes, schemas. |
| [`n8nac-reference`](skills/n8nac-reference/SKILL.md) | Raw `n8nac --help` tree, 68 command/subcommand blocks. Source of truth for "does this command exist?" — **if not in `reference.md`, it does not exist.** |
| [`n8n-architect`](https://github.com/EtienneLescot/n8n-as-code) (companion plugin) | Schema-First Research, workflow authoring rules, AI/LangChain patterns, Common Mistakes. Owned by Etienne's `n8n-as-code` plugin. |

**Rule:** before running `npx n8nac <cmd> --help` interactively, `grep` the cheat-sheet, then the
reference file. Only fall back to live `--help` if both fail — and treat that as a sign to regenerate
the reference (`bash scripts/dump-n8nac-help.sh > skills/n8nac-reference/reference.md`).

## Cheat-Sheet — User asks X → run Y

**Use these BEFORE inventing flags or grepping `--help`.** If the user's intent matches a row, run
the linked skill / command verbatim. If no row matches, ask the user — do not guess.

| User intent | Exact command |
|---|---|
| "find credential <name>" / "which cred is X" / "list Dropbox creds in this project" | `/n8n-autopilot:find-credential <pattern>` (project-scoped by default; add `--type <credType>` or `--project all`) |
| "list n8n projects" / "which projects exist" / "show projects on instance" | `/n8n-autopilot:find-project` |
| "switch workspace to project X" | verify env target via `npx n8nac env list --json`, then `npx n8nac env update <env> --project-name "<X>"` then `/n8n-autopilot:check-mcps` |
| "show active project / instance binding" | `npx n8nac workspace status --json` — project + sync folder only. **env-blind**: its env field reports the GLOBAL active env, NOT the session env. For "which env am I on" use `npx n8nac env list --json` (never infer the session env from `workspace status`) |
| "build a workflow that does X" | `/n8n-autopilot:build-workflow "<description>"` (prose pipeline) |
| "build/edit with hard-enforced gates" (experimental) | `/n8n-autopilot:build-workflow-v2 "<description>"` — JS-orchestrated, gate-checks as control flow |
| "build a whole multi-workflow STACK" / "orchestrator + sub-workflows from one use case" (experimental) | `/n8n-autopilot:build-stack-v2 "<end-to-end use case>"` (or `extend "<stack>" "<change>"`) — decompose → handover contracts + mermaid → bottom-up build via build-workflow-v2 |
| "help me plan an n8n workflow" / "I want to automate X but don't know how" / rough idea only | `/n8n-autopilot:stack-intake "<one-line idea>"` — guided interview → writes a PRP for build-stack-v2 |
| "deploy <file>.workflow.ts" | `/n8n-autopilot:deploy <file>.workflow.ts` |
| "pull every remote-only workflow / fix mirror drift" | `/n8n-autopilot:mirror-sync` |
| "which env/instance is this session on" / "pin session to env X" / "why was my env command blocked" | `/n8n-autopilot:session-env` (explains model + reports session-vs-global). Pin per-session via `.claude/settings.json` `env` block `N8NAC_ENVIRONMENT=<env>` (or `export`/`--env`) — **never `env use`** (mutates shared global, blocked by clobber-guard). See [docs/rules/gates.md](docs/rules/gates.md). |
| "fix stale credential IDs in workflows" | `/n8n-autopilot:sync-credentials --fix-workflows` (project-scoped) |
| "regenerate inventory / list of nodes" | `/n8n-autopilot:inventory` |
| "data table CRUD" (create/seed/list/drop tables in n8n) | `/n8n-autopilot:data-tables` |
| "give feedback" / "report friction" / "feedback zum plugin" | `/n8n-autopilot:feedback` (interview); `/n8n-autopilot:feedback sync` pushes centrally (consent-gated) |
| "pull schemas" / "update node schemas" | `/n8n-autopilot:pull-schemas` |
| "check setup / MCP / instance health" | `/n8n-autopilot:check-mcps` |
| "find a workflow by name" | `npx n8nac find <query> --json` (use `--remote` for instance-side, default = local+remote) |
| "test a workflow" (any trigger) | native n8n MCP, server `n8n-native`: pinned `prepare_test_pin_data` → `test_workflow` (no side effects, default); live `execute_workflow` manual only with real test data. Nothing is activated. Setup + contract: [docs/rules/testing.md](docs/rules/testing.md) |
| "test by hand in the UI" (MCP server not registered) | `/n8n-autopilot:test-manual <workflowId>` (resolves UI URL → waits for execution-id → inspects run) |
| "show executions of workflow <id>" | `npx n8nac execution list --workflow-id <id>` |
| "inspect a specific execution" | `npx n8nac execution get <executionId> --include-data` |
| "resolve workflow URL for UI" | `npx n8nac workflow present <id> --json` |
| "pull workflow from instance" | `npx n8nac pull <id>` |
| "refresh remote state without overwriting local" | `npx n8nac fetch <id>` |
| "create a NEW credential type" / before `credential create` | `npx n8nac credential schema <type>` FIRST — n8n rejects unknown credential fields with HTTP 400 (e.g. `httpHeaderAuth` requires `allowedDomains`). Never guess the credential body shape |
| "activate a stack / parent workflow that calls sub-workflows" | publish each sub-workflow (the `executeWorkflow`/`mcpTrigger` target) in the n8n UI BEFORE activating the parent — `push` does not auto-publish; parent activation fails on an unpublished child |

**Multi-project rule:** every credential / workflow operation runs in the
**workspace-pinned project's scope**. Verify the project pin via `npx n8nac workspace status --json`
before any cred-touching operation (for the session *env*, use `env list --json` — `workspace status` is env-blind). If uncertain whether it's the right project, use
`/n8n-autopilot:find-project` first.

## Hook Gates (enforced by `PreToolUse`)

Three fail-closed gates protect against drift, cross-session env clobbering and shipping a broken workflow. One
`PreToolUse` entry (`matcher: Bash|PowerShell` → `scripts/pretooluse-gate.sh`, reads the hook's stdin JSON) runs
them in order for BOTH shell tools. One-line summary;
**full mechanism + bypass + reconciliation in [docs/rules/gates.md](docs/rules/gates.md).**

- **Push-Gate** (`scripts/push-gate.sh`) — blocks `npx n8nac push` when remote status is
  `CONFLICT`/`MODIFIED_BOTH`/`DIVERGED`/`REMOTE_ONLY`, and always blocks `resolve --mode keep-*|local-wins`.
  Default fix: `pull` → re-edit → `push --verify`. Bypass only after explicit user OK to discard
  remote: `N8N_AUTOPILOT_ALLOW_LOCAL_WINS=1 <cmd>`.
- **Push-Lint-Gate** (`scripts/push-lint-gate.sh`) — blocks `npx n8nac push` unless
  (1) every node type + typeVersion exists on the RUNNING instance (`instance-node-check.mjs` → the
  instance's MCP `get_node_types`; n8nac's own preflight falls back to its bundled catalogue),
  (2) every top-level parameter exists for the node's typeVersion (`param-version-check.py` reads the
  `@version` gates from `node-info`; n8n ignores a key of another version silently) and
  (3) the compiled JSON passes the deterministic lint (`lint-workflow.py`): an error strategy on every
  top-level workflow with external calls (`settings.errorWorkflow` or a wired error output),
  `continueOnFail` only with a downstream `$json.error` check, no unwired error output, no orphan /
  dead-trigger nodes, balanced expressions, no 0-node compile, `availableInMCP: true`. In the build
  pipelines a lint block is a fix loop (author → validate → repush, max 3). Bypass only after explicit
  user OK: `N8N_AUTOPILOT_SKIP_LINT=1 <cmd>`.
- **`n8n-native` (plugin MCP server) is test/read-only** and always targets the instance of the
  pinned session env — setup per env: `npx n8nac native-mcp configure <env> --token-stdin --level 2`
  ([docs/rules/testing.md](docs/rules/testing.md)). Workflows change via `.workflow.ts` + push.
- **Env-Gate** (`scripts/enforce-env.sh`) — one env per session. Blocks any instance-touching
  command with no explicit env (`export N8NAC_ENVIRONMENT=<env>` / inline / `--env`), and blocks
  `env use`/`env pin` unconditionally (they mutate the shared GLOBAL active env). Pin via
  `N8NAC_ENVIRONMENT`, never `env use`.

## Setup

→ `/n8n-autopilot:init-repo [target-dir]` scaffolds everything (dir layout, CLAUDE.md/README/
`.gitignore`/`.mcp.json`/`.env.example`, env flow, schemas, verify). Manual step-by-step,
plugin install, and the legacy in-repo `./n8nac-config.json` note: **[docs/rules/setup.md](docs/rules/setup.md).**

## Auto-Reactions on SessionStart

SessionStart hooks emit `AUTOPILOT_ACTION_REQUIRED: <slash-command>` lines when state is stale and an
automated fix exists. When you see such a line, **run that exact slash-command immediately, without
asking the user first** — these signals fire only when the action is safe and idempotent.

| Signal source | Hook? | Trigger | Auto-action |
|---|---|---|---|
| `check-schema-versions.sh` | direct (SessionStart) | Cached schema older than latest npm version | `/n8n-autopilot:pull-schemas --community-only --packages <list>` |
| `check-installed-nodes.sh` | indirect (via `setup-check.sh` §7) | Community node installed on instance, no cached schema | `/n8n-autopilot:pull-schemas --community-only --packages <list>` |
| `check-credential-freshness.sh` | direct (SessionStart) | Workflow references credential ID not on instance | `/n8n-autopilot:sync-credentials --fix-workflows` |
| `check-mirror-drift.sh` | direct (SessionStart) | Remote workflow exists on instance with no local file | `/n8n-autopilot:mirror-sync` |

Hard rule: parse the literal slash-command after `AUTOPILOT_ACTION_REQUIRED:` and execute it. Do not
paraphrase, do not skip the `--packages` list, do not bundle multiple signals into one call — run
each line as written.

**Probe/action symmetry (rule for writing probes).** Because that signal is mandatory, a probe may only
emit it when the named action can actually resolve the condition — the probe must test *what the action
fixes*, not a proxy for it. Two probes violated this and fired every session into a guaranteed no-op
(5.3.3): the credential probe matched on ID while the fixer joins on name, and the mirror probe trusted
`n8nac list`'s status without checking whether the file was already on disk. When the condition is real
but not auto-fixable, print `INFO:` with the manual remedy instead. Guarded by
`bash scripts/test-probe-symmetry.sh`.

Signals NOT auto-triggered (informational only — surface to user, do not auto-run):
- `check-instance-cache.sh` (`INFO:` — `.n8n-autopilot/instance-cache.json` missing, older than 24 h, or
  built for a different env. Rebuilding hits the instance twice and takes ~30 s, past the hook budget;
  the build skills refresh it themselves before dispatching. See *Instance cache* below).
- `check-inventory-freshness.sh` (`INFO:` — inventory regeneration is expensive).
- `check-feedback-pending.sh` (`INFO:` — unsynced feedback exists; offer `/n8n-autopilot:feedback`, needs consent).
- `check-plugin-version.sh` (`INFO:` — installed plugin is behind the latest release; gotcha/env-gate hooks may be missing. Tell the user to run `claude plugin update n8n-autopilot` — env-changing, their call, never auto-run).
- `check-custom-nodes-resolution.sh` (`INFO:` — workflows use community node packages but n8nac has no custom-node source loaded, so `skills search`/`node-info` return **empty instead of erroring** for those types. Treat an empty research result for a listed package as a resolution failure, not as "the node does not exist". `pull-schemas` does NOT fix it — different mechanism; the remedy is `n8nac-custom-nodes.json` / `env update --custom-nodes-path`, which the plugin cannot author for you).
- `check-workspace-migration.sh` — in-repo `./n8nac-config.json`. **Never tell the user to delete it:** n8nac 2.5.0 reads an in-repo config, and with no home config present it is the live one (deleting it destroys every env binding). The probe reports *live* vs *superseded* and stays silent when it is simply live ([docs/rules/setup.md](docs/rules/setup.md)).

## Instance cache — the agents' view of what already runs here

`bash scripts/build-instance-cache.sh` writes two files (both gitignored, both instance-specific):

| File | For | Rule |
|---|---|---|
| `.n8n-autopilot/instance-brief.md` (~7 KB) | reading whole | node types proven on ACTIVE workflows + active workflows as candidate references |
| `.n8n-autopilot/instance-cache.json` (~80 KB at 78 workflows) | grepping | per-workflow detail: file, trigger, `nodeTypes`, `credentialNames`; plus `credentials[]`, `customNodes[]` |

**Why it exists.** `schemas/` holds n8nac's own node knowledge — instance-*independent*, and read by no
agent. `docs/INVENTORY.md` is prose for humans. `.n8n-state.json` holds a sync hash. So nothing on disk
described the instance, and the research phase went looking for prior art in the public 7.7k-template
corpus while 78 working workflows sat next door. `n8nac skills node-info` reports every version n8n ever
shipped (`switch` → `[1,2,3,3.1,3.2,3.3,3.4]`) and knows nothing about the target — *exists* and *exists
here* are different claims, and only the second survives a push.

**Consumers:** `n8n-researcher` (mandatory local-prior-art step before the template lookup, returns
`referenceWorkflow`) · `n8n-node-verifier` (`provenOnInstance`) · `n8n-author` (reads the prior-art file;
takes credential ids from `credentials[]` instead of inventing them) · `n8n-stack-architect` (reuses
existing workflows as callees instead of rebuilding them). Refreshed by the build skills before dispatch.

**typeVersion ground truth = the instance, at push time.** The cache holds no `typeVersion` (`pull`
drops it, `list --json` never had it), and the bundled n8nac catalogue is stamped for a fixed n8n
version (2.4.1 → n8n 2.38.7) that customer instances do not run. The authority is the instance's own MCP
`get_node_types`, which the push-lint gate queries for every type@version before a push
([docs/rules/testing.md](docs/rules/testing.md)).

## Entry Point & Deploy

- Create/build/scaffold a workflow → `/n8n-autopilot:build-workflow "description"` (full pipeline
  incl. deploy). **NEVER write workflow code directly** — Phase 0 research via n8nac is mandatory.
- Deploy → `/n8n-autopilot:deploy <workflow-name>.workflow.ts`

## Tool Boundaries

**n8nac is PRIMARY** for all node research, authoring, sync, test, and ops. The full annotated
command catalogue (PRIMARY + Operations + workflow design-quality rules) lives in
**[docs/reference/n8nac-commands.md](docs/reference/n8nac-commands.md)** — backed by the
`n8nac-cheatsheet` / `n8nac-reference` skills (the SSOT). Quick reference: [docs/OVERVIEW.md](docs/OVERVIEW.md).

**Auth failures that are not what they look like** — a `403` on one endpoint while the same key works
everywhere else means the API KEY LACKS THAT SCOPE (n8n has no fallback to the user's global role, and
never backfills scopes onto an existing key — re-pasting it cannot help); `env auth` is stored per
ENVIRONMENT, not per instance target, so environments sharing a target each need their own
`env auth set`. Both, plus how to get an activation failure's real cause out of n8n:
**[docs/troubleshooting/auth-and-scopes.md](docs/troubleshooting/auth-and-scopes.md)**.

Three lifecycle steps n8nac **cannot** automate (full procedures in
[docs/troubleshooting/manual-detours.md](docs/troubleshooting/manual-detours.md)):
- **MCP publish** — workflows with `mcpTrigger` need a manual "Publish" click in the n8n UI after every push.
- **Testing** is no longer a manual detour: every trigger type runs headless via native MCP pin-data tests ([docs/rules/testing.md](docs/rules/testing.md)); `/n8n-autopilot:test-manual <id>` stays for hand-driven UI runs.
- **DataTable CRUD** — no `datatable` subcommand; use the `/n8n-autopilot:data-tables` skill (curl carve-out for `/api/v1/data-tables` only).

**Feedback loop** — SessionEnd / PreCompact / resume auto-capture non-PII friction signals locally; `/n8n-autopilot:feedback`
review distills them into typed `finding` records and consent-gated POSTs them to the ingest webhook
(no gh needed) → **one public GitHub issue per finding** (incl. reporter = OS username);
maintainer-side `feedback-triage` agent dedups/ranks the open issues.
Detail: [docs/rules/feedback-loop.md](docs/rules/feedback-loop.md).

### NEVER do these (enforced by hooks)
- Never call the n8n REST API directly (curl, wget, urllib, Invoke-RestMethod, fetch, HTTP Request node) — the PreToolUse guard blocks all of these against `/api/v1`. **Exception:** `/api/v1/data-tables` via the `data-tables` skill (loop its `curl` for polling; never read n8nac's internal `~/.n8n-manager/secrets.json` for the key).
- Never delete workflows without explicit user confirmation.
- Never write workflow JSON by hand — always Decorator-TS format.
- **Never ask the user to activate/publish a workflow in the n8n UI.** A failing
  `npx n8nac workflow activate <id>` means the WORKFLOW IS BROKEN (node issues — most often an
  external-service node without a `credentials:` block) — **except when the error names a referenced
  sub-workflow**: then the cause is publish ORDER (callees must be published/active before the caller,
  bottom-up), not a defect. Fix the order, do not "fix" the file. Diagnose + fix + re-push + re-activate;
  cross-check the instance with a known-good trivial workflow if unsure. UI-activation requests are
  a bug, not a workaround. (Only exception: `mcpTrigger` publish — a documented n8n API gap.)
- **Archived workflows are read-only** — `push` is rejected; unarchive (n8n UI) or recreate, no code-fix loop.
