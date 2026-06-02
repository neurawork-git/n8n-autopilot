# n8n Workflow Development — n8n-autopilot Plugin

This repo uses the **n8n-autopilot plugin** for Claude Code.
Workflows are TypeScript (Decorator format). Never write n8n JSON by hand.

> **Reference n8nac version: 2.2.1** (minimum 2.2.0). All setup, workspace, and credential flows below target the v2 manager-backed storage model. Single source of truth: `REFERENCE_N8NAC_VERSION` constant in `scripts/setup-check.sh`. Bump procedure: update the constant, sync README badges + `plugin.json`, add CHANGELOG entry.

## Knowledge skills — read BEFORE inventing CLI surface

| Skill | When to read |
|---|---|
| [`n8nac-cheatsheet`](skills/n8nac-cheatsheet/SKILL.md) | Default first stop. "Which command for X?" — curated table covering 60+ common operations across workspace, env, workflows, executions, credentials, recipes, schemas. |
| [`n8nac-reference`](skills/n8nac-reference/SKILL.md) | Raw `n8nac --help` tree, 74 subcommands. Read when the cheat-sheet does not cover a request. Source of truth for "does this command exist?" — if not in `reference.md`, it does not exist. |
| [`n8n-architect`](https://github.com/EtienneLescot/n8n-as-code) (companion plugin) | Schema-First Research, workflow authoring rules, AI/LangChain patterns, Common Mistakes. Owned by Etienne's `n8n-as-code` plugin. |

**Rule:** before running `npx n8nac <cmd> --help` interactively, `grep` the cheat-sheet, then `grep` the reference file. Only fall back to live `--help` if both lookups fail — and treat that as a sign to regenerate the reference (`bash scripts/dump-n8nac-help.sh > skills/n8nac-reference/reference.md`).

## Cheat-Sheet — User asks X → run Y

**Use these BEFORE inventing flags or grepping `--help`.** If the user's intent matches a row, run the linked skill / command verbatim — do not fish through `--help`. If no row matches, ask the user, do not guess.

| User intent | Exact command |
|---|---|
| "find credential <name>" / "which cred is X" / "list Dropbox creds in this project" | `/n8n-autopilot:find-credential <pattern>` (project-scoped by default; add `--type <credType>` or `--project all`) |
| "list n8n projects" / "which projects exist" / "show projects on instance" | `/n8n-autopilot:find-project` |
| "switch workspace to project X" | `npx n8nac workspace set-project --project-name "<X>"` then `/n8n-autopilot:check-mcps` |
| "show active project / instance binding" | `npx n8nac workspace status --json` |
| "build a workflow that does X" | `/n8n-autopilot:build-workflow "<description>"` (prose pipeline) |
| "build/edit with hard-enforced gates" (experimental) | `/n8n-autopilot:build-workflow-v2 "<description>"` — JS-orchestrated, gate-checks as control flow |
| "build a whole multi-workflow STACK" / "orchestrator + sub-workflows from one use case" (experimental) | `/n8n-autopilot:build-stack-v2 "<end-to-end use case>"` (or `extend "<stack>" "<change>"`) — decompose → handover contracts + mermaid → bottom-up build via build-workflow-v2 |
| "help me plan an n8n workflow" / "I want to automate X but don't know how" / user has only a rough idea | `/n8n-autopilot:stack-intake "<one-line idea>"` — guided interview → writes a PRP for build-stack-v2 |
| "deploy <file>.workflow.ts" | `/n8n-autopilot:deploy <file>.workflow.ts` |
| "pull every remote-only workflow / fix mirror drift" | `/n8n-autopilot:mirror-sync` |
| "which env/instance is this session on" / "pin session to env X" | `npx n8nac env list --json` · pin per-session via `export N8NAC_ENVIRONMENT=<env>` or per-call `npx n8nac --env <env> …` |
| "fix stale credential IDs in workflows" | `/n8n-autopilot:sync-credentials --fix-workflows` (project-scoped) |
| "regenerate inventory / list of nodes" | `/n8n-autopilot:inventory` |
| "data table CRUD" (create/seed/list/drop tables in n8n) | `/n8n-autopilot:data-tables` |
| "give feedback" / "report friction" / "feedback zum plugin" | `/n8n-autopilot:feedback` (interview); `/n8n-autopilot:feedback sync` pushes centrally (consent-gated) |
| "pull schemas" / "update node schemas" | `/n8n-autopilot:pull-schemas` |
| "check setup / MCP / instance health" | `/n8n-autopilot:check-mcps` |
| "find a workflow by name" | `npx n8nac find <query> --json` (use `--remote` for instance-side, default = local+remote) |
| "test schedule/manual/error-trigger workflow" / "non-HTTP test" | `/n8n-autopilot:test-manual <workflowId>` (resolves UI URL → waits for execution-id → inspects run) |
| "show executions of workflow <id>" | `npx n8nac execution list --workflow <id>` |
| "inspect a specific execution" | `npx n8nac execution get <executionId> --include-data` |
| "resolve workflow URL for UI" | `npx n8nac workflow present <id> --json` |
| "pull workflow from instance" | `npx n8nac pull <id>` |
| "refresh remote state without overwriting local" | `npx n8nac fetch <id>` |

**Multi-project rule:** every credential / workflow operation runs in the **workspace-pinned project's scope**. Verify the pin via `npx n8nac workspace status --json` before any cred-touching operation. If the answer to "is this the right project?" is uncertain, use `/n8n-autopilot:find-project` first.

## Push-Gate (drift protection — enforced by hook)

The `PreToolUse` hook `scripts/push-gate.sh` blocks two operations by default:

1. **`npx n8nac push <file>`** when `npx n8nac list --search <id>` reports status `CONFLICT`, `MODIFIED_BOTH`, `DIVERGED`, or `REMOTE_ONLY` — i.e. remote has changed since the last local fetch.
2. **`npx n8nac resolve <id> --mode keep-current|keep-local|local-wins`** — always blocked, because it overwrites remote with local in one step.

Bypass (single command, only after explicit user authorization that the remote change should be discarded):

```bash
N8N_AUTOPILOT_ALLOW_LOCAL_WINS=1 <re-run the n8nac command>
```

Default reconciliation path when push is blocked:
1. `npx n8nac pull <id>` — remote wins, sync local
2. Re-edit the local file with your intended change
3. `npx n8nac push <id> --verify` again

The hook auto-runs `npx n8nac fetch <id>` before judging status, so the verdict is always against fresh remote state. Workflows without an `id:` field (new creations) are never blocked.

## Env-Gate (one env per session — enforced by hook)

A session works in exactly ONE n8n env (instance + project). The `PreToolUse` hook
`scripts/enforce-env.sh` **fail-closed BLOCKS** any instance-touching `npx n8nac` command that
resolves to NO explicit env — otherwise it would silently hit the mutable GLOBAL active env
(`env use`), which is shared across sessions and wrong when sessions target different projects.

An env is "resolved" (command allowed) when ANY of these holds:
- session default set: `export N8NAC_ENVIRONMENT=<env-name>` (the normal per-session pin), or
- inline: `N8NAC_ENVIRONMENT=<env-name> npx n8nac …`, or
- per-call flag: `npx n8nac --env <env-name> …`.

Local-only subcommands never touch an instance and are never gated:
`skills`, `convert`, `convert-batch`, `workspace`, `env`, `setup`, `setup-modes`, `telemetry`,
`update-ai`, `help`, `--version`. Everything that contacts the instance (`list`, `find`, `pull`,
`push`, `fetch`, `verify`, `test`, `test-plan`, `resolve`, `promote`, `execution`, `credential[s]`,
`workflow`) is gated.

`npx n8nac env list --json` lists envs + their projects. n8nac itself throws
`Unknown workspace environment: <name>` on a bogus env name (so a typo fails closed, never silently
falls back). The SessionStart hook `scripts/report-session-env.sh` prints the active session env
(name + host + project) so you always know where you are. **Verified routing**: `N8NAC_ENVIRONMENT`
and `--env` both route instance commands to the named env's instance, independent of the global active.

## Setup

**Brand-new repo? One command:**
→ `/n8n-autopilot:init-repo [target-dir]` — scaffolds dir layout + CLAUDE.md/README/.gitignore/.mcp.json/.env.example, runs the v2.2 setup flow (`setup --mode connect-existing` + `workspace pin-instance` + `set-sync-folder`), pulls schemas, verifies.

**Manual (if you prefer step-by-step):**
1. Install both plugins (n8n-autopilot + Etienne's companion):
   ```bash
   claude plugin marketplace add neurawork-git/n8n-autopilot
   claude plugin install n8n-autopilot@n8n-autopilot

   claude plugin marketplace add EtienneLescot/n8n-as-code
   claude plugin install n8n-as-code@n8nac-marketplace
   ```
   The companion plugin (Etienne) provides the `n8n-architect` skill that owns schema-research, authoring rules, AI/LangChain rules, etc. n8n-autopilot does workflow lifecycle orchestration (init-repo, build-workflow pipeline, deploy, sync-credentials, inventory, data-tables).
2. Bind workspace to n8n instance (n8nac >= 2.2 stores config in user home, NOT the repo):
   ```bash
   printf "%s" "$N8N_API_KEY" | npx n8nac setup --mode connect-existing \
     --host "$N8N_API_URL" --api-key-stdin --json
   npx n8nac workspace pin-instance --instance-id <id-from-setup-output>
   npx n8nac workspace set-sync-folder workflows
   # Optional, for multi-project instances:
   npx n8nac workspace set-project --project-name Personal
   ```
3. `/n8n-autopilot:pull-schemas` — populate `schemas/nodes/` (gitignored, instance-specific)
4. Verify: `/n8n-autopilot:check-mcps` (or runs auto via SessionStart hook; expects workspace status `bound`)

**Migrating from n8nac < 2.2?** Legacy `./n8nac-config.json` is migrated via `npx n8nac workspace migrate-v1 --write`. The plugin does not delete the legacy file; `init-repo` warns and stops.

## Auto-Reactions on SessionStart

SessionStart hooks emit `AUTOPILOT_ACTION_REQUIRED: <slash-command>` lines when state is stale and an automated fix exists. When you see such a line in hook output, **run that exact slash-command immediately, without asking the user first** — these signals only fire when the action is safe and idempotent.

| Signal source | Hook? | Trigger | Auto-action |
|---|---|---|---|
| `check-schema-versions.sh` | direct (SessionStart) | Cached schema older than latest npm version | `/n8n-autopilot:pull-schemas --community-only --packages <list>` |
| `check-installed-nodes.sh` | indirect (called by `setup-check.sh` Section 7) | Community node installed on instance, no cached schema | `/n8n-autopilot:pull-schemas --community-only --packages <list>` |
| `check-credential-freshness.sh` | direct (SessionStart) | Workflow references credential ID that does not exist on instance | `/n8n-autopilot:sync-credentials --fix-workflows` |
| `check-mirror-drift.sh` | direct (SessionStart) | Remote workflow exists on instance with no local file (local mirror incomplete) | `/n8n-autopilot:mirror-sync` |

Hard rule: parse the literal slash-command after `AUTOPILOT_ACTION_REQUIRED:` and execute it. Do not paraphrase, do not skip the `--packages` list, do not bundle multiple signals into one call — run each line as written.

Signals NOT auto-triggered (informational only):
- `check-inventory-freshness.sh` (`INFO:` prefix — surface to user, do not auto-regenerate; inventory regeneration is expensive).
- `check-feedback-pending.sh` (`INFO:` prefix — unsynced autopilot feedback records exist; offer `/n8n-autopilot:feedback`, do NOT auto-run — giving/syncing feedback needs user consent).
- `check-workspace-migration.sh` — flags legacy in-repo `./n8nac-config.json` (suggests `npx n8nac workspace migrate-v1 --write`) and `workspace status: dry-run` / `migration-required` (suggests `npx n8nac workspace migrate --write`). Migrations move files on the user's filesystem — surface the block to the user verbatim, do NOT auto-run.

## Entry Point

When the user asks to create, build, or scaffold a workflow:
→ `/n8n-autopilot:build-workflow "description"` — full pipeline incl. deploy
→ **NEVER write workflow code directly** — Phase 0 research via n8nac is mandatory.

## Deploy

→ `/n8n-autopilot:deploy <workflow-name>.workflow.ts`

## Tool Boundaries

### ALWAYS use n8nac (PRIMARY)
- Node research: n8nac MCP tools (`search_n8n_knowledge`, `get_n8n_node_info`, `search_n8n_docs`, `search_n8n_workflow_examples`)
- Validate (local): `npx n8nac skills validate <file>` — Agent-Pipelines: `--strict --json` für strukturierten Output
- Deploy + verify: `npx n8nac push <file> --verify` — push and immediately validate remote state
- Test: `npx n8nac test <id> --data '...'` (or `--query` for GET webhooks; `--prod` for production URL — workflow must be active)
- Test plan: `npx n8nac test-plan <id> --json` — infer trigger type + suggested payload before testing
- Activate: `npx n8nac workflow activate <id>`
- Deactivate: `npx n8nac workflow deactivate <id>`
- Credentials: `npx n8nac credential list/get/create/delete/schema <type>`
- Credential recipes (n8nac >= 2.2): `npx n8nac credentials recipes/inventory/starter-kits --json` — shared catalogue (openai-native, slack-oauth, postgres, …); `npx n8nac credentials ensure <recipeId>` creates from recipe; `npx n8nac credentials test <id-or-recipeId>` verifies live
- Executions: `npx n8nac execution list/get`
- Workflow URL resolution: `npx n8nac workflow present <id> --json` — never string-concat `<host>/workflow/<id>`

### Operations (all via n8nac CLI)
- Health check: `bash scripts/setup-check.sh`
- List/search workflows: `npx n8nac list` / `npx n8nac find <query>` — **default excludes archived**; use `--include-archived` for all, `--only-archived` for archive-only; `--json --search --sort --limit --local --remote` for scripted/agent use
- **Archivierte Workflows sind read-only** — `push` wird abgelehnt. Kein Code-Fix-Loop; erst unarchivieren (n8n UI) oder neu erstellen.
- Get workflow details: `npx n8nac pull <workflowId>`
- Deploy template: `npx n8nac skills examples search/list/info/download <id>` → `npx n8nac push`
- Execution history: `npx n8nac execution list --workflow <id>`
- Execution details: `npx n8nac execution get <execId> --include-data`
- Community node search: n8nac MCP `search_n8n_knowledge` + `docs/COMMUNITY_NODES.md`
- Workflow fix after error: Claude reads error → fixes .workflow.ts → `n8nac skills validate` → `n8nac push --verify` → `n8nac test`
- Conflict resolution: `npx n8nac resolve <workflowId>` — resolve local/remote conflict before push
- Remote validation: `npx n8nac verify <workflowId>` — validate remote workflow against local schema
- Credential check: `npx n8nac workflow credential-required <id>` — exit 0 = all present, exit 1 = missing
- Remote state fetch: `npx n8nac fetch <workflowId>` — explizit Remote-State abrufen
- Format conversion: `npx n8nac convert <file>` / `npx n8nac convert-batch <dir>` — JSON ↔ TypeScript
- AI-Kontext: `npx n8nac update-ai` — AGENTS.md + AI-Kontext regenerieren
- Multi-Environment: `npx n8nac env list/add/update/pin/remove` — Environment-Management (mehrere n8n-Instanzen pro Repo)
- Aktives Environment wechseln: `npx n8nac env use <name>` (alias: `env pin <name>`)
- Workspace ↔ Instanz-Binding: `npx n8nac workspace pin-instance` / `clear-instance` / `set-sync-folder` / `set-project` / `status` / `migrate` / `migrate-v1`
- Setup (Erstkonfiguration): `npx n8nac setup --mode <managed-local|connect-existing|generation-only>` (Modus-Liste: `npx n8nac setup-modes`). `init` / `init-auth` / `init-project` aus n8nac < 2.2 sind **entfernt** — niemals verwenden.
- Node-Referenz: `npx n8nac skills node-schema <name>` — schnelles TypeScript-Snippet (`--json` für strukturierten Agent-Output); `skills node-info <name> --json` — vollständige Node-Info; `skills related <query>` — verwandte Nodes; `skills guides` — Tutorials; `skills list --nodes/--docs/--guides` — Enumerierung
- `@workflow` Decorator: optionales `description`-Feld (Round-trip-fähig, erscheint in n8n UI und `n8nac list`-Output)

### MCP Access Lifecycle (Workflows mit mcpTrigger) — MANUELL

Workflows, die `@n8n/n8n-nodes-langchain.mcpTrigger` enthalten, exponieren einen MCP-Endpoint.
Dieser Endpoint ist NUR nach Publish in der n8n-UI erreichbar. `n8nac push` erzeugt einen neuen
Draft — die bisher publizierte Version bleibt stehen, der MCP-Endpoint kann gegenüber dem
neuen Draft veraltet sein.

**Regel:** Nach jedem Push/Update eines Workflows mit `mcpTrigger`:
1. URL via n8nac auflösen: `npx n8nac workflow present <workflowId> --json`
2. n8n-UI öffnen unter der URL aus dem Output
3. "Publish"-Button klicken
4. User bestätigt Publish-Status im Completion Report

n8nac kann nicht publishen. `deploy` skill und Phase 2 (Path D) der `build-workflow` pipeline
zeigen einen prominenten Hinweis statt automatischem Re-Publish.

### Non-HTTP-Trigger Testing — MANUELL

`n8nac test` kann nur Webhook-/Chat-/Form-Trigger auslösen. Für `schedule`, `manual`, `errorTrigger`:

→ **`/n8n-autopilot:test-manual <workflowId>`** bündelt den ganzen Detour (URL auflösen → auf
execution-id warten → Run inspizieren). Manuell sind die Schritte:

1. URL via n8nac auflösen: `npx n8nac workflow present <workflowId> --json`
2. n8n-UI unter dieser URL öffnen
3. "Execute Workflow"-Button klicken
4. User meldet `execution-id` an Claude
5. Claude inspiziert via `npx n8nac execution get <id> --include-data`

Die `build-workflow` pipeline (Path B) stoppt automatisch und prompted den User entsprechend.

### DataTable Lifecycle (curl carve-out)

n8nac has no `datatable` subcommand. Managing DataTable resources (create/list/seed/drop tables, columns, rows) is done via the n8n public REST API at `/api/v1/data-tables`. The PreToolUse curl-block has an explicit carve-out for this path only.

→ Use `/n8n-autopilot:data-tables` skill — it documents every endpoint and provides ready-to-paste curl recipes (incl. heredoc-safe JSON for umlauts on Windows).

### Feedback Loop (capture + central feedback)

A `SessionEnd` hook (`scripts/capture-feedback.sh`) silently appends NON-PII friction signal counts
(an anchored signal taxonomy) from each session to
`.n8n-autopilot/feedback/events.ndjson` in the consumer repo (gitignored). A `SessionStart` probe
(`scripts/check-feedback-pending.sh`) emits an `INFO:` nudge when unsynced records exist.

- `/n8n-autopilot:feedback` (default = **review**) — one-shot: reviews the session (auto-captured
  signals + file-level design metrics from `workflows/*.workflow.ts` + a qualitative pass),
  LLM-redacts to neutral insights, runs the deterministic PII gate, shows the result, then pushes.
- `/n8n-autopilot:feedback interview` — manual Q&A only. `… show` — list pending. `… sync` — push only.
- **Push** = ONE labelled GitHub issue on `neurawork-git/n8n-autopilot-internal` via `gh issue create`
  (one path, no fallback). **Side-effecting + consent-gated**: shows every record, requires explicit
  confirmation. Live web-server ingestion = future TODO.
- **PII (defense-in-depth):** auto-capture stores only counts + repo basename. Before ANY push,
  `scripts/redact-check.js` deterministically BLOCKS unknown keys + free-text matching
  email/path/URL/long-digit/token/customer-name patterns — on top of the LLM redaction. No hook ever
  pushes; capture is local-only.

### Workflow design quality (enforced by `workflow-reviewer`)

The `workflow-reviewer` agent checks 15 points incl. design-quality:
native-first (prefer `IF`/`Switch`/`Filter`/`Set` over Code nodes), no silent failures
(`continueOnFail`/`onError:continue` without an error branch), memory/large-data (Code nodes on big
DB result sets → OOM; use `SplitInBatches`/pagination), descriptions present, no overlapping node
positions. Deeper authoring rules stay with the companion `n8n-architect` plugin.

Auto-activated workflow-pattern guidance skills (org-learned, concrete examples):
- `n8n-orchestration-patterns` — fan-out/fan-in, parallel sub-workflows (branch-split trap,
  `executionOrder: v0`, DataTable fan-in), synchronous batch + fast-return webhook.
- `n8n-structured-extraction` — LLM extraction/classification via a real JSON schema (Information
  Extractor / Text Classifier), never Agent+prompt.
- `/n8n-autopilot:data-tables` — now also documents the upsert node shape (3-part requirement) +
  usage patterns (fan-in store, idempotency/dedup, error rows).

### NEVER do these (enforced by hooks)
- Never call n8n REST API directly (curl, fetch, HTTP Request node) — **exception:** `/api/v1/data-tables` via the `data-tables` skill
- Never delete workflows without explicit user confirmation
- Never write workflow JSON by hand — always Decorator-TS format
