# Changelog

All notable changes to **n8n-autopilot** are documented here. Versions follow [Semantic Versioning](https://semver.org/).

## [5.0.0] — 2026-06-08

### ⚠ BREAKING — minimum n8nac raised 2.2.0 → 2.3.0

The plugin now requires **n8nac ≥ 2.3.0**. n8nac 2.3 removed the `workspace pin-instance` /
`set-project` / `set-sync-folder` / `migrate*` mutators and the `instance-target` command, replacing
them with the environment-centric `env` model that the plugin's setup, init-repo, and credential flows
now depend on. Setups pinned to n8nac < 2.3 will fail the SessionStart `setup-check` (hard error) and
the init/credential flows will break. Since n8nac is run via `npx` (always latest), most users upgrade
transparently; anyone pinning an older n8nac must move to ≥ 2.3.0.

### Changed — n8nac compatibility bump 2.2.1 → 2.3.6 (environment-centric config model)

n8nac 2.3.x replaced the workspace-mutation config model with an **environment-centric** model.
`n8nac workspace` is now read-only (`status` / alias `get` only); all instance-binding, project, and
sync-folder config moved onto `env`. Native cross-env `promote` was added in 2.3.0.

**Removed commands** (no longer exist — do not use):
- `n8nac workspace pin-instance` / `clear-instance`
- `n8nac workspace set-project` / `clear-project`
- `n8nac workspace set-sync-folder` / `clear-sync-folder`
- `n8nac workspace migrate` / `migrate-v1`
- `n8nac instance-target` (entire command + subcommands add/list/remove/update)

**New / replacement commands:**
- `n8nac env add <name> --base-url <url> --workflows-path workflows` — create + bind an environment
- `printf '%s' "$N8N_API_KEY" | n8nac env auth set <name> --api-key-stdin` — store API key
- `n8nac env use <name>` — activate (alias of `env pin`)
- `n8nac env update <name> --project-name <P>` — replaces `workspace set-project`
- `n8nac promote [path] --from <env> --to <env>` — native cross-env promotion

**Plugin-side updates:**
- `REFERENCE_N8NAC_VERSION` bumped 2.2.1 → 2.3.6; minimum version bumped 2.2.0 → 2.3.0 in
  `scripts/setup-check.sh`
- `scripts/dump-n8nac-help.sh` — dropped the dead `instance-target` node;
  `skills/n8nac-reference/reference.md` regenerated against 2.3.6
- `scripts/setup/`, `skills/init-repo/`, `README.md`, `CLAUDE.md`, `skills/n8nac-cheatsheet/` —
  all setup and mutation references migrated from `workspace pin-instance` / `set-project` /
  `set-sync-folder` to `env add` / `env auth set` / `env update` / `env use`
- `skills/find-credential/`, `skills/find-project/` — workspace-mutation calls removed
- `scripts/check-workspace-migration.sh` — neutered; the migrate commands no longer exist, so
  stale `./n8nac-config.json` detection now instructs the user to **delete the file manually**
  (config lives in `~/n8nac-config.json` + `~/.n8n-manager/`; no migrate command available)

**Kept unchanged:** `n8nac workspace status --json` (read-only effective-context resolver, still
valid), `n8nac setup --mode <mode>` facade (still exists; binding now follows via env commands),
per-session `N8NAC_ENVIRONMENT` pin model and the `enforce-env.sh` / `report-session-env.sh` hooks.

### Added — session-env isolation: clobber-guard + `session-env` skill + isolation test

Closes the one hole in the per-session env model: `env use` / `env pin` mutate the machine-GLOBAL
active env (shared across all shells and Claude sessions), so a session running it silently re-points
every other un-pinned session. Empirically reproduced (15/17 → the two clobber-guard assertions failed
before the fix), then closed.

- **`scripts/enforce-env.sh` clobber-guard** — `env use` / `env pin` are now **blocked
  unconditionally** (exit 2), with a clear message steering to `N8NAC_ENVIRONMENT`. Deliberate
  machine-default changes bypass via `N8N_AUTOPILOT_ALLOW_ENV_USE=1`. Read-only `env list` / `env
  status` stay allowed.
- **`scripts/test-env-isolation.sh`** — empirical proof harness (17 assertions, read-only against
  instances, never runs `env use`): routing via `N8NAC_ENVIRONMENT` + `--env` to distinct hosts,
  the **safety invariant** (global active untouched by session pins, re-asserted at end), `workspace
  status` env-blindness, and full gate + clobber-guard behaviour. Verified `=== 17 passed, 0 failed ===`.
- **`skills/session-env/`** (`/n8n-autopilot:session-env`) — documents the model (global active vs
  per-session `N8NAC_ENVIRONMENT`), the three resolution scopes, both enforcement hooks, the
  `workspace status` gotcha, and runs the verification/test. Linked from the CLAUDE.md Env-Gate
  section + cheat-sheet.
- **Env-blind call-site fixes** — three skills used `workspace status` (env-blind) as a SESSION
  project resolver and so scoped to the wrong project when the session was pinned elsewhere:
  `find-credential/search.js`, `find-project/list.js`, and `sync-credentials/fix-workflows.js` (the
  last writes credential IDs into workflow files → real corruption risk). All three now resolve the
  active project from `env status --json` (session-aware). `workspace status` is deliberately kept
  for global-binding/liveness checks (`setup-check.sh`, `check-installed-nodes.sh`) — not forbidden.
- **Workflow env-propagation verified** — empirically confirmed (probe Workflow, generic agent +
  the real `n8n-tester` agentType) that `N8NAC_ENVIRONMENT` propagates session → Claude Workflow
  runtime → `agent()` subagent Bash, so the v2/stack pipelines' "env is inherited, run bare" design
  routes to the correct instance. Both agents resolved the session env + host; bare instance commands
  ran against the right env and left the global active untouched.

## [4.9.0] — 2026-05-30

### Added — build-stack-v2 (workflow-stack orchestrator) + stack-intake interview

Lifts the deterministic v2 discipline from a single workflow to a whole **stack** (an orchestrator plus
the sub-workflows it calls via Execute Workflow nodes).

- **`build-stack-v2`** skill (`skills/build-stack-v2/stack.workflow.js`) — JS-orchestrated, two modes:
  - **GREENFIELD** — Plan (decompose a PRP into sub-WFs + handover contracts) → Document
    (`docs/<stack>.architecture.md` with a deterministically-composed mermaid graph + contract tables)
    → Build (**topological bottom-up**, one `build.workflow.js` hop per sub-WF, each child's real
    `workflowId` fed into its parent's Execute Workflow node) → Report.
  - **EXTEND** — Mirror (`mirror-sync`) → Comprehend (reconstruct the call-graph from `executeWorkflow`
    refs in the local mirror) → Delta-plan → Apply (new sub-WFs bottom-up via `build.workflow.js`, then
    changed sub-WFs / orchestrator rewiring via `edit.workflow.js`) → Report.
  - A failed child build **halts** its dependents (no building on a broken foundation) and escalates;
    `status:'success'` only when every planned sub-WF built green. Reuses build-workflow-v2's scripts
    verbatim via the `workflow()` hook (1-level nesting), so every sub-WF gets the same hard gates.
- **2 agentType definitions** — `n8n-stack-architect` (decompose + delta-plan; `skills:`
  n8n-orchestration-patterns / n8n-structured-extraction / n8nac-cheatsheet / n8n-architect) and
  `n8n-stack-comprehender` (reconstruct the DAG from code, reconcile/regenerate the architecture doc).
  Both read-only.
- **`stack-intake`** skill — a guided, classic interview for users **not yet experienced with n8n**:
  asks about overall inputs, outputs, a concrete worked example, expected behavior, external systems,
  volume, and failure handling, then synthesizes a PRP-style use-case file
  (`docs/stack-prps/<slug>.prp.md`) ready for `build-stack-v2`. Plans only — never touches the instance.

### Note

- **Experimental + test-gated.** End-to-end stack runs should only be trusted once `build-workflow-v2`
  (greenfield + edit) is green against the target instance and the `skills:` pass-through is verified.
  The scaffold ships now; the live stack test follows that gate.

## [4.8.1] — 2026-05-29

### Added — plugin-testing skill + session-state capture

- **`skills/plugin-testing`** — the canonical (and only supported) way to test plugin changes: commit →
  push to the private repo → install FROM that GitHub repo → restart → verify registration. Documents
  the hard anti-patterns (no cache hand-copying, no directory-pointer marketplace, no hand-edited
  `settings.json`, `/reload-plugins` insufficient for new agents) and a verification probe.

## [4.8.0] — 2026-05-29

### Added — JS-orchestrated workflow pipeline v2 (experimental) + env-awareness

**Deterministic gates via Claude Code Workflow scripts.** Where `build-workflow` (v1) is prose the
model is *asked* to follow, v2 encodes the gate sequence as JS control flow the model cannot skip,
reorder, or short-circuit (validate before push; test only after `push --verify`; `status:success`
only after the execution is inspected; bounded fix-loops as real `while` counters).

- **`build-workflow-v2`** skill — two modes: GREENFIELD (`build.workflow.js`) and EDIT
  (`edit.workflow.js`, local-first: refresh to remote base → patch → drift-safe push). Subagent roles
  are extracted into namespaced agentTypes (`agents/n8n-*.md`), resolved in-workflow as
  `n8n-autopilot:n8n-*` (proven: Workflow resolves+spawns namespaced plugin agents).
- **`mirror-sync`** skill (`sync.workflow.js`) — pulls every remote-only workflow so the repo mirrors
  the instance (discover `/REMOTE/i` status → fan-out `pull` → verify). Establishes the local-first
  invariant the edit flow relies on. Auto-triggered by the SessionStart drift probe.
- **8 agentType definitions** — `n8n-researcher`, `n8n-node-verifier` (adversarial param contract),
  `n8n-comprehender`, `n8n-author`, `n8n-validator`, `n8n-deployer` (drift-aware), `n8n-tester`,
  `n8n-mirror`. Reusable across v1/v2 and via the Agent tool directly.

### Added — n8n environment safety (one env per session)

- **`scripts/enforce-env.sh`** (PreToolUse hard gate) — blocks any instance-touching `npx n8nac`
  command that resolves to NO explicit env (no `--env`, no inline/session `N8NAC_ENVIRONMENT`),
  preventing silent operations against the shared GLOBAL active env. Local/config subcommands
  (skills/convert/workspace/env/setup/…) are never gated. Fail-closed.
- **`scripts/report-session-env.sh`** (SessionStart) — states the session's env (instance + project)
  up front; warns when none is pinned and only the shared global-active env would be used.
- Model: **one env per Claude session** via `N8NAC_ENVIRONMENT` (per-repo default in
  `.claude/settings.json` `env` block). **Workflow subagents inherit it** (verified empirically) — so
  agents run `npx n8nac` BARE and hit the right (instance + project); prompt-injected `--env` flags were
  tried and dropped unreliably, so agent defs now FORBID `--env`/`env list`/env-probing. Different
  sessions target different projects simultaneously — never a global `env use` switch. An n8nac env =
  (instance host + n8n project). `setup-check`/`report-session-env` resolve via `env status` (honors
  `N8NAC_ENVIRONMENT`), not `workspace status` (which only sees the global active env).
- Fan-out reliability: a **retry-once pass** catches subagents that finish without emitting their
  StructuredOutput result (idempotent ops like `pull` re-run safely) — prevents false under-reporting.
- **`scripts/check-mirror-drift.sh`** (SessionStart) — emits `AUTOPILOT_ACTION_REQUIRED:
  /n8n-autopilot:mirror-sync` only when remote-only workflows exist (no blind every-session pull).
- `init-repo` step 6.5 runs `mirror-sync` after schema pull so a fresh repo starts as a full mirror.

## [4.7.0] — 2026-05-29

### Added — idempotent CLAUDE.md section anchoring for existing repos

`init-repo` previously only wrote a templated `CLAUDE.md` for brand-new repos; an existing repo with
its own `CLAUDE.md` was skipped, so the autopilot guidance never landed there.

- New `skills/init-repo/scripts/ensure-claude-section.js` — idempotently anchors a marker-delimited
  n8n-autopilot section (`<!-- n8n-autopilot:start -->`…`<!-- n8n-autopilot:end -->`) into `CLAUDE.md`:
  creates the file if missing, refreshes the block in place if markers exist (no duplication),
  appends to a foreign CLAUDE.md, and SKIPs a full-template CLAUDE.md (sentinel) unless `--force`.
  Content outside the markers is never touched.
- New section template `skills/init-repo/assets/templates/CLAUDE-section.md` — entry points,
  SessionStart auto-reactions, design-quality rules, pattern-skill pointers, NEVER rules.
- `init-repo.sh` runs it after scaffolding (non-fatal on failure). Also runnable standalone on any
  existing repo: `node …/ensure-claude-section.js --workspace .`.

## [4.6.0] — 2026-05-29

### Added — workflow-pattern guidance skills (org-learned, concrete examples)

Distilled from real production memories + debates into reusable, example-driven guidance.

- **`n8n-orchestration-patterns`** (new auto-activated skill) — fan-out / fan-in and parallel
  sub-workflow execution. Covers the branch-split trap (`executionOrder: v1` runs serially), Pattern A
  (`executionOrder: v0` layer interleaving), **Pattern B = Wait-OFF + DataTable fan-in (recommended)**,
  Pattern B2 (resumeUrl, veto grey-zone), Pattern C (queue mode), synchronous-batch + fast-return
  webhook, and the error-output-not-`continueOnFail` rule. With TS config examples.
- **`n8n-structured-extraction`** (new auto-activated skill) — LLM extraction/classification via a
  real JSON schema using `informationExtractor` / `textClassifier`, never an AI-Agent "return JSON"
  prompt. Documents the reasoning-model failure modes (`{"output":...}` wrap, enum/umlaut violations)
  and a full Information-Extractor schema example (typed + described fields, ASCII-safe enums).
- **`data-tables`** extended — the workflow-node **upsert shape** (3-part requirement:
  `filters.conditions` keyName+condition+keyValue **and** `matchingColumns`) + usage patterns
  (fan-in store, idempotency/dedup via upsert, error rows, cross-run state, count-race safety).

## [4.5.0] — 2026-05-29

### Added — Design-quality learnings + `/feedback` session-review-redact-push flow

A second analysis dimension — workflow **design
anti-patterns**, which the operational-friction taxonomy missed. Surfaced after the user asked about
Code-node overuse and memory limits; both confirmed real (calibrated): Code nodes ~2.5:1 over native
conditional nodes, and a real n8n-pod **OOM** from Code nodes iterating >10k Postgres rows.

- **`/n8n-autopilot:feedback` is now a one-shot review flow** (default action): resolves the session
  transcript (`latest-transcript.js`), summarizes auto-captured signals, measures file-level design
  quality from `workflows/*.workflow.ts` (Code-vs-native, missing descriptions, overlapping node
  positions), does a qualitative pass, **LLM-redacts to neutral insights**, runs a deterministic PII
  gate, shows the result, and pushes. `interview` / `show` / `sync` remain as sub-actions.
- **Deterministic PII gate** `scripts/redact-check.js` — allowlist (known keys + signal names,
  numeric values, basename-only `repoLabel`) + denylist (email / abs-path / URL / long-digit / IBAN /
  token / configured customer names via `N8N_AUTOPILOT_PII_NAMES`). `sync.sh` runs it as a hard
  gate before every push (defense-in-depth on top of the LLM redaction).
- **`workflow-reviewer` checklist 10 → 15 points** — adds native-first (prefer IF/Switch/Filter/Set
  over Code), no silent failures (`continueOnFail`/`onError:continue`), memory/large-data (OOM),
  descriptions present, no overlapping nodes.
- **`capture-feedback.sh`** adds two transcript-detectable design signals: `memory_oom`,
  `continue_on_fail`.
- **`n8n-code-javascript` guidance** — new "When NOT to use a Code node (native-first)" section +
  OOM-on-large-data caveat; stopped listing "filtering" as a default Code use-case.

## [4.4.0] — 2026-05-29

### Added — `/n8n-autopilot:test-manual` + friction fixes from production-run analysis

Acts on the HIGH/MED improvement candidates surfaced by the v4.3.0 feedback-loop run analysis.
Conservative, additive fixes — the push-gate BLOCKING logic is unchanged.

- **New skill `/n8n-autopilot:test-manual <workflowId>`** — packages the non-HTTP-trigger
  (schedule/manual/errorTrigger) test detour (the #1 friction class, `non_http_test`=760) into one
  flow: resolves the n8n UI URL via `workflow present`, waits for the user-reported execution-id,
  then inspects the run via `execution get --include-data`. Read-only against the instance. Wired
  into `deploy` step 6 and CLAUDE.md.
- **Conflict-resolve churn reduced** (`conflict_resolve`=688, biggest friction) — push-gate BLOCKED
  messages and `deploy` step 3 now include a "back up local before pull" recipe (`cp <file>
  <file>.local-bak` → pull → diff → re-apply as a patch), so a local edit is re-applied as a small
  diff instead of being re-typed after `pull` overwrites it.
- **Validation guidance** (`validate_fail`=577) — `deploy` step 2 now points to the
  `n8n-validation-expert` guidance skill when validation fails (n8nac's validator text is terse and
  upstream-owned).

### Fixed

- `deploy` step 6 referenced a non-existent "step 9" for the non-HTTP manual-execution notice; now
  points to the new `/n8n-autopilot:test-manual` skill.

## [4.3.0] — 2026-05-28

### Added — Feedback Loop (SessionEnd capture + `/n8n-autopilot:feedback` skill + central GitHub sink)

A standardized way for the plugin to learn from real-world usage, grounded in an exhaustive analysis
of 33 Claude Code sessions from a real consumer repo.

- **Auto-capture** — new `SessionEnd` hook `scripts/capture-feedback.sh` silently extracts NON-PII
  friction signal counts from the session transcript (anchored taxonomy: `non_http_test`,
  `conflict_resolve`, `validate_fail`, `mcptrigger_detour`, `schema_gap`, `tool_error`, …) and
  appends one `kind:"event"` NDJSON record to `.n8n-autopilot/feedback/events.ndjson` in the consumer
  repo (gitignored). Fire-and-forget; never blocks shutdown; stores only counts + repo basename.
- **Interactive feedback** — new skill `/n8n-autopilot:feedback` runs a short process-feedback
  interview (questions derived from the top friction classes) → `process.ndjson`. `show` lists
  pending records; `sync` pushes everything centrally.
- **Central sink** — `sync` creates ONE labelled GitHub issue on `neurawork-git/n8n-autopilot-internal`
  via `gh issue create` (single transport path, no fallback). Consent-gated: every record is shown
  and a PII warning is given before pushing. A live feedback web server is a documented TODO
.
- **Nudge** — new `SessionStart` probe `scripts/check-feedback-pending.sh` emits an `INFO:` line
  (never `AUTOPILOT_ACTION_REQUIRED:`) when unsynced records exist.
- **Analysis finding** — the historical assumption that push-gate blocks were a top pain is NOT
  supported: `push_gate_block` is unobservable in historical transcripts (reclassified live-only).
  Bare-keyword grep was found to massively overcount (`"BLOCKED"`→`blockedBy` JSON, `"CONFLICT"`→SQL
  `ON CONFLICT`), so all heuristics are anchored to emitted strings.

## [4.2.2] — 2026-05-20

### Fixed — Skill frontmatter YAML parse errors + n8nac >= 2.2 quiet-skip in community-node check

Two bugs found via `claude --debug` log inspection in a real consumer repo:

**1. YAML parse failure in two skills** — Claude Code's loader reported `[WARN] Failed to parse YAML frontmatter` for `skills/n8nac-cheatsheet/SKILL.md` and `skills/build-workflow/SKILL.md`. Both skills were silently dropped from the session — only 14 of 16 plugin skills were loading. Root cause: an unquoted `description:` value contained `<word>: ` (e.g. "common workflows: lookup"), which js-yaml parses as a nested mapping. Fixed by wrapping both descriptions in quotes (single for one, double for the other due to embedded apostrophes / backticks) and replacing the inline colons with em-dashes where readability allowed.

**2. `check-installed-nodes` warned about missing `.env` even on bound workspaces** — n8nac >= 2.2 stores the API key in the secure manager store (`~/.n8n-manager/`), NOT in a workspace `.env`. The schema-coverage probe needs the key to query `/community-packages`, but it cannot retrieve it from the secure store. Pre-4.2.2 the script just printed "ℹ️  .env not found — skipping" on every session, which was misleading (looked like a setup issue, was actually the expected state). Now resolves auth in three tiers:

1. `.env` with `N8N_API_URL` + `N8N_API_KEY` — authoritative, runs the probe.
2. No `.env` but workspace bound — silent skip with explanatory note ("workspace bound (n8nac >= 2.2 keeps API key in secure store; cannot probe `/community-packages`). Run `/n8n-autopilot:pull-schemas` after installing new community nodes.").
3. Neither — quiet "skipping" (genuinely unconfigured).

No skill changes, no manifest changes beyond the version bump.

## [4.2.1] — 2026-05-20

### Fixed — SessionStart hook path resolution (consumer workspace, not plugin dir)

Two SessionStart-hook scripts still resolved their working directory to `$CLAUDE_PLUGIN_ROOT` (the plugin install dir under `~/.claude/plugins/cache/…`) instead of `$PWD` (the consumer repo where Claude Code is actually running). v3.7.1 fixed this for `check-credential-freshness.sh` and `check-workspace-migration.sh` but missed two others; this patch closes the gap.

- `scripts/check-schema-versions.sh` — now reads `schemas/_index.json` from the consumer workspace. Previously checked the plugin's own cache which never reflects the consumer's installed nodes.
- `scripts/check-installed-nodes.sh` — now reads `schemas/_index.json` and `.env` from the consumer workspace. This explains the long-standing "ℹ️ check-installed-nodes: .env not found — skipping." that the consumer repo saw on every session despite having a populated `.env` in its repo root.

Both files now follow the pattern documented in `check-credential-freshness.sh`: `REPO_DIR="$PWD"` with a comment block clarifying why `$CLAUDE_PLUGIN_ROOT` is the wrong primitive for workspace lookups.

No skill changes, no manifest changes beyond the version bump.

## [4.2.0] — 2026-05-20

### Added — n8nac knowledge skills (full CLI reference + curated cheatsheet)

Two new knowledge skills end the "agent fishing through `--help`" pattern:

**`n8nac-reference`** (`skills/n8nac-reference/`)
- Auto-generated, machine-walked `n8nac --help` tree.
- 74 subcommands across 26 top-level groups (workspace, env, instance-target, setup, credentials, credential, workflow, execution, skills, plus 14 root-level commands like `list`, `find`, `pull`, `push`, `promote`, `verify`, `test`, `test-plan`, `fetch`, `resolve`, `convert`, `convert-batch`, `mcp`, `update-ai`).
- Source of truth: **if a command is not in `reference.md`, it does not exist** — agents must not invent CLI surface.
- Regenerated via `scripts/dump-n8nac-help.sh` (re-run after any n8nac upgrade).
- Strict-mode help parser (column-3 anchor + alias-strip) keeps the file at ~1500 lines rather than the runaway 11000+ lines the loose parser produced on first attempt.

**`n8nac-cheatsheet`** (`skills/n8nac-cheatsheet/`)
- Curated "user intent → exact command" table, ~60 rows, grouped into Workspace, Multi-Environment, Instance Targets, Workflow Lifecycle, Testing & Execution, Credentials (CRUD + recipes), Schemas/Node Info, Telemetry.
- Highlights the singular `credential` vs. plural `credentials` distinction (most common "command not found" footgun), the push-gate bypass env var, and the n8nac >= 2.2 setup commands that replaced the removed `init` / `init-auth` / `init-project`.
- Gotchas section enumerates the 10 most common silent-failure patterns (project visibility, test trigger limits, mcpTrigger publish, archived read-only, etc.).

CLAUDE.md now has a "Knowledge skills" block above the cheat-sheet pointing at both, with the rule: **grep the cheatsheet → grep the reference → only then run `--help` live**. The `n8n-architect` companion skill is also linked as the canonical source for workflow authoring rules.

### Added — Multi-project awareness + push-gate (drift protection) + cheat-sheet

Three structural defects fixed after a real session showed Claude fishing through `--help`, inventing CLI subcommands (`skills list-credentials`), and injecting cross-project credential IDs:

**1. New skill `/n8n-autopilot:find-credential`** (`skills/find-credential/`)
- Search live credentials by name pattern, **scoped to the workspace-pinned project by default**.
- Flags: `--type <credType>`, `--project <name|id|all>`, `--exact`, `--json`.
- Returns table grouped by project + paste-ready TypeScript snippets.
- Shows count of cross-project matches as a footnote when default-scoped (no leak, but visible).
- Replaces the ad-hoc "`n8nac credential list --json | grep`" pattern that ignored project scope and routinely picked the wrong project's credential ID.

**2. New skill `/n8n-autopilot:find-project`** (`skills/find-project/`)
- Enumerates every n8n project visible on the active instance (derived from `credential list --json` → `shared[].name` / `shared[].id` — works without the Enterprise `/api/v1/projects` endpoint).
- Marks the workspace-pinned project, prints the exact `workspace set-project` command to switch.
- One audited instance shipped seven projects; agents had no way to see the others before this.

**3. Push-gate hook (`scripts/push-gate.sh`)** — wired into `hooks.json` PreToolUse(Bash)
- BLOCKS `npx n8nac push <file>` when `n8nac list --search <id>` returns status `CONFLICT` / `MODIFIED_BOTH` / `DIVERGED` / `REMOTE_ONLY`. Hook auto-runs `n8nac fetch <id>` first, so the verdict is always against fresh remote state.
- BLOCKS `npx n8nac resolve <id> --mode keep-current|keep-local|local-wins` unconditionally — this command silently overwrites remote with local.
- Single bypass: `N8N_AUTOPILOT_ALLOW_LOCAL_WINS=1 <re-run command>` (requires explicit user authorization that remote changes are to be discarded).
- New workflows (file with no `id:` field) are never blocked.

**4. `sync-credentials --fix-workflows` now project-scoped by default**
- Joins workflow credential references against ONLY credentials owned by the active workspace project. Cross-project name collisions no longer rewrite IDs into the wrong project.
- Header now reports `Project scope: <name> (<id>)` and "Skipped N credential(s) owned by other projects" so the scope is visible in every run.
- New flag `--all-projects` disables the filter (rare, used when migrating workflows between projects).

**5. CLAUDE.md cheat-sheet at the top of the file**
- "User asks X → run Y" table covering every common request (find credential, list projects, switch project, build, deploy, fix creds, inventory, data-tables, executions, etc.).
- Push-gate section documenting block conditions and the override env var.
- Multi-project rule stated up front: every credential / workflow operation runs in the workspace-pinned project's scope; verify the pin before touching credentials.

**6. `check-mcps` skill + `setup-check.sh` Section 6** now print the project visibility table on every health check / SessionStart, so multi-project state is visible without an explicit query.

**Why this matters (real incident pattern):** workspace pinned to project A, instance has projects A–G, `n8nac credential list --json` returns creds from all visible projects. Agent matches by name only → injects credential ID from project F into a workflow in project A → push succeeds, runtime fails with "credential not accessible". After 4.2.0: `find-credential` shows only project A by default, `sync-credentials --fix-workflows` will not rewrite cross-project IDs, push-gate refuses to silently overwrite remote changes.

## [4.1.0] — 2026-05-19

### Changed — skills now invoke bundled scripts, no inline executable code

Three skills previously embedded large inline bash/node blocks (50+ lines of executable code in the SKILL.md body). That pattern caused Claude to read the skill, paraphrase the logic, and re-implement it ad-hoc — which in turn led to skills "meandering" (writing one-off helper scripts into the consumer repo, probing wrong API paths, misclassifying nodes). The skill body should be intent and pointers; the code lives in colocated scripts.

Per the skill-creator norm (`skill-name/scripts/`), skill-specific executable code now lives inside the skill folder itself.

**`pull-schemas`** — new bundled `scripts/`:
- `discover-types.sh` — extracts node types from `workflows/**/*.workflow.ts`
- `fetch-one.sh` — fetches one indexed node via `npx n8nac skills node-info` (exit 1 = "not in n8nac index, try Stage 2")
- `fetch-pkg.js` — extracts every exported node class from a published npm package directly
- `rebuild-index.js` — walks `schemas/nodes/**` and rebuilds `schemas/_index.json`
- `run.sh` — orchestrator. The skill body now just says `bash $CLAUDE_PLUGIN_ROOT/skills/pull-schemas/scripts/run.sh [flags]`.

**`inventory`** — new bundled `scripts/aggregate.js`:
- Walks workflows, extracts node types / triggers / LLM models / credentials / workflow names, classifies them, renders the Markdown report. No more inline grep+xargs+node+jq pipelines that Claude had to stitch together.
- Best-effort enriches the Summary header with remote counts via `npx n8nac list --json --include-archived`.

**`sync-credentials`** — new bundled `scripts/`:
- `list.js` — fetches `npx n8nac credential list --json`, prints a clean table + ready-to-paste TypeScript snippets.
- `fix-workflows.js` — the rewrite logic: tolerant block-parsing regex, surgical `id:` replacement inside each matched `credentials: { … }` block (never global), conflict + orphan reporting. The previous skill body asked Claude to "use a tolerant regex — recommended approach: a node script with proper TS-source parsing"; now there is one.

All three SKILL.md bodies are now thin pointers (~50 lines each) — when to invoke, which flag does what, where the scripts live. No executable code in the skill prose.

Verified end-to-end against a real consumer repo: pull-schemas pulled 16 core schemas, inventory rendered the report, sync-credentials --fix-workflows --dry-run correctly detected 16 stale credential references plus 5 orphans.

## [4.0.0] — 2026-05-19

### Breaking

- **n8n-autopilot is now CLI-only.** All `mcp__n8n-as-code__*` tool references removed across `build-workflow`, `deploy`, `pull-schemas`, `check-mcps`, `sync-credentials`, and `agents/n8n-researcher.md`. The namespace never had a stable upstream source — the npm `n8nac mcp` entry-point crashes in every published version (missing `mcp` package dependency in `@n8n-as-code/skills`), and Etienne Lescot's `n8n-as-code` plugin ships skill knowledge, not an MCP server. All schema research / node-info / validation now goes through `npx n8nac skills …`.
- **Companion plugin `n8n-as-code@n8nac-marketplace` (Etienne Lescot) is now expected.** It provides the `n8n-architect` skill that owns Schema-First Research, Workflow Authoring Rules, AI/LangChain rules, Common Mistakes, Operating Loop, etc. n8n-autopilot delegates these and focuses on what it uniquely adds: workspace lifecycle (`init-repo`), build pipeline orchestration (`build-workflow`), deploy with auto-fix loop (`deploy`), `pull-schemas` Stage 2 npm-extraction, `sync-credentials --fix-workflows`, `inventory`, `data-tables`, and SessionStart diagnostics.
- **Four redundant knowledge skills removed** because they overlap with `n8n-architect`:
  - `n8n-workflow-patterns/`
  - `n8n-node-configuration/`
  - `n8n-validation-expert/`
  - `n8n-expression-syntax/`
  Kept: `n8n-code-javascript`, `n8n-code-python` — both genuinely cover Code-node specifics that `n8n-architect` does not touch.
- **`agents/n8n-researcher.md` removed.** Build-workflow Phase 0 calls the CLI directly (`npx n8nac skills search/node-info/related/examples`); Etienne's `n8n-architect` is the canonical researcher.
- **`.mcp.json.example` + `skills/init-repo/assets/templates/mcp.json` removed.** No `.mcp.json` is scaffolded into new repos.
- **`init-repo` scaffolds 4 files instead of 5** (CLAUDE.md, README.md, .gitignore, .env.example) — `.mcp.json` is gone.
- **`check-mcps` skill rewritten.** No more "MCP tool registration" check (no MCP). Now verifies: n8nac CLI version, workspace bound, companion plugin enabled.

### Fixed

- **`claude plugin path` references removed everywhere.** That command does not exist in the Claude Code CLI (`claude plugin --help` shows only `list/install/uninstall/marketplace/update`). Replaced with: `$CLAUDE_PLUGIN_ROOT` env var (in plugin-context scripts), slash-command pointers (`/n8n-autopilot:check-mcps`), or "runs auto via SessionStart hook" (for verification hints). This was a pre-existing bug from Jochen's era that earlier versions silently inherited.
- **MCP version pinning rolled back.** v3.7.0 pinned `.mcp.json` invocations to `n8nac@2.2.0` after observing 2.2.1 crashes. Investigation showed `npx n8nac mcp` crashes in every published n8nac version — `require('mcp')` without a declared dep is an architectural issue, not a regression. Pinning was Symptom-treatment that did not help; removed.

### Added

- **Companion-plugin health check in `setup-check.sh`.** Warns when `n8n-as-code@n8nac-marketplace` is not enabled in user settings, with install instructions inline.

### Migration guide for consumer repos (3.x → 4.0)

1. Install the companion plugin (one-time):
   ```bash
   claude plugin marketplace add EtienneLescot/n8n-as-code
   claude plugin install n8n-as-code@n8nac-marketplace
   ```
2. Bump n8n-autopilot: `claude plugin install n8n-autopilot@n8n-autopilot` (auto-pulls 4.0.0).
3. Remove any workspace-local `.mcp.json` that only contained the `n8n-as-code` entry — it was never functional in any version. If your `.mcp.json` has other entries (e.g. `n8n-mcp@latest` from czlonkowski), drop only the `n8n-as-code` block.
4. Verify: `/n8n-autopilot:check-mcps`. Expect green on all rows.

## [3.7.1] — 2026-05-19

### Fixed
- **SessionStart hooks looked at the wrong directory.** Both `check-workspace-migration.sh` and `check-credential-freshness.sh` resolved `REPO_DIR` from `$CLAUDE_PLUGIN_ROOT`, which points at the plugin install path — not the consumer workspace. Result: workspace-local `n8nac-config.json` and stale credential refs in consumer repos were silently invisible (false negatives). Now both scripts use `$PWD`, which the hook runtime sets to the user's workspace.
- **`check-workspace-migration.sh` was content-blind.** Now reads the `version` field of any found `n8nac-config.json` and surfaces the right reason: `version: 1 | 2` → pre-2.2 schema (legacy data); `version: 4` → schema is current but the file is in the wrong location for n8nac 2.2 (which expects user home). Both cases still resolve to the same `workspace migrate-v1 --write` command.
- **Path-quoting bug in the new version probe.** Inline `node -e "require('$WIN_PATH')"` failed under Git-Bash on Windows due to backslash handling. Switched to reading the file with `cat … | node -e "JSON.parse stdin"` for portability.

## [3.7.0] — 2026-05-18

### Changed (breaking for repos still on n8nac < 2.2)
- **n8nac reference version pinned to 2.2.1** (minimum 2.2.0). Single source of truth: `REFERENCE_N8NAC_VERSION` constant in `scripts/setup-check.sh`. README badges, root `CLAUDE.md`, `init-repo` skill, and `plugin.json` all reference this.
- **`init-repo` skill rewritten for the v2.2 setup flow.** The removed n8nac commands `init` / `init-auth` / `init-project` no longer appear anywhere in the plugin. Replacement flow:
  1. `npx n8nac setup --mode connect-existing --host <url> --api-key-stdin --json`
  2. `npx n8nac workspace pin-instance --instance-id <id>`
  3. `npx n8nac workspace set-sync-folder workflows`
  4. Optional: `npx n8nac workspace set-project --project-name <n>`
- **`scripts/setup-check.sh` rewritten.** Workspace-binding check no longer looks for `./n8nac-config.json` (file relocated to user home in n8nac 2.2). Now calls `npx n8nac workspace status --json` and distinguishes `ready` / `dry-run` (migration pending) / unknown. Live-connectivity probe pulls the host from the workspace-status JSON instead of grepping a file.
- **`scripts/check-credential-freshness.sh`** init hint updated to `npx n8nac setup --mode connect-existing`.
- **Templates updated.** `skills/init-repo/assets/templates/`: removed `n8nac-config.json.example`; the file is no longer scaffolded into consumer repos. `gitignore` keeps the legacy entries (for the migrate-v1 transition window) but documents why. `CLAUDE.md` + `README.md` setup sections rewritten for the new flow.
- **Plugin docs (`CLAUDE.md`, `README.md`, `README.de.md`)** synced to the new flow. Added a top-level "Reference n8nac version" callout pointing at `REFERENCE_N8NAC_VERSION`.

### Added
- **`build-workflow` Phase 0 — Step 0 added: community-template lookup is now mandatory before node-by-node discovery.** `npx n8nac skills examples search/info/download` now appears at the top of the Phase 0 tools table and as Step 0 in the pipeline. Threshold: if a template matches ≥70 % (same trigger family + target service + comparable transformations), download it as the seed and run discovery only for added/changed nodes. Adapting a validated template is cheaper, less hallucination-prone, and lands on a community-proven pattern. The Phase-0 sub-agent (`n8n-researcher`) already had these tools — this change wires them into the Lead-Claude pipeline doc so the sub-agent actually gets asked to use them.
- **`scripts/check-workspace-migration.sh` + SessionStart hook.** New informational diagnostic that flags two migration-pending states: (1) legacy `./n8nac-config.json` in the repo (suggests `workspace migrate-v1 --write`); (2) `workspace status` returning `dry-run` / `migration-required` (suggests `workspace migrate --write`). Surfaced verbatim to Claude; deliberately NOT in the `AUTOPILOT_ACTION_REQUIRED` auto-execute list because migrations move files on the user's filesystem and should be run consciously. Wired into `hooks/hooks.json` after `check-credential-freshness`.
- **`npx n8nac workflow present <id>` integration.** The `deploy` skill (mcpTrigger publish notice) and the manual-execution notices in root `CLAUDE.md` now resolve the user-facing URL via `workflow present` instead of string-concatenating `<host>/workflow/<id>`. Avoids host-mismatch bugs across multi-env setups.
- **Credentials recipe / inventory surface (n8nac 2.2).** `sync-credentials` skill documents `npx n8nac credentials recipes`, `credentials inventory`, `credentials ensure <recipeId>`, and `credentials test` for richer reporting and shared-recipe creation. Root `CLAUDE.md` "ALWAYS use n8nac" section lists them as first-class commands.
- **Workspace-binding commands** (`workspace set-sync-folder`, `workspace set-project`, `workspace migrate`, `workspace migrate-v1`) added to the root `CLAUDE.md` operations list and both READMEs' command tables.
- **Promote** (`npx n8nac promote --from --to`) **deliberately not yet integrated.** Multi-environment workflow promotion is in n8nac 2.2 but most consumer repos don't have multiple environments. Will revisit when there's a real user.

### Migration guide for existing consumer repos

1. Bump n8nac: `npx clear-npx-cache && npx n8nac@latest --version` (expect ≥ 2.2.0).
2. If `./n8nac-config.json` exists in the repo: `npx n8nac workspace migrate-v1 --write` (one-shot; moves config to `~/n8nac-config.json` + `~/.n8n-manager/`).
3. If `npx n8nac workspace status --json` returns `status: "dry-run"`: `npx n8nac workspace migrate --write`.
4. Verify: `bash scripts/setup-check.sh` should print "All checks passed".

## [3.6.1] — 2026-05-18

### Added
- **`README.de.md`** — full German translation of the README. Language-switcher banner at the top of both READMEs follows the GitHub `README.<locale>.md` convention.

## [3.6.0] — 2026-05-18

### Added
- **`/n8n-autopilot:data-tables`** — new skill for managing n8n DataTable resources (CRUD on tables, columns, rows) via the public REST API at `/api/v1/data-tables`. PreToolUse curl-block has an explicit carve-out for this single path; all other API endpoints stay blocked.
- **Auto-Reactions on SessionStart** — hook scripts now emit machine-parsable `AUTOPILOT_ACTION_REQUIRED: <slash-command>` lines. Claude runs the literal command without asking the user, when the action is safe and idempotent. Mapping is documented in `CLAUDE.md`.
- **`--packages` flag in `/n8n-autopilot:pull-schemas`** — targets specific npm community-node packages for refresh (used by the auto-reaction signal).
- **`--fix-workflows` mode in `/n8n-autopilot:sync-credentials`** — rewrites stale credential IDs in local `.workflow.ts` files by matching credential name.
- **`/n8n-autopilot:init-repo`** — one-command repo bootstrap (was added in 3.5.0 prep, shipped together).
- **`/n8n-autopilot:inventory`** — aggregates node/LLM/credential usage from local workflows into `docs/INVENTORY.md`.
- **`docs/OVERVIEW.md`** — one-page summary.
- **`CHANGELOG.md`** — this file.

### Changed
- **All skills now spec-conformant per skill-creator standard.** Bundled reference docs moved from sibling-of-`SKILL.md` into `references/` subdirectories. TOCs added to large reference files (>300 lines). Every skill has explicit `user-invocable: true/false` in its frontmatter.
- **`n8nac` minimum version bumped to 2.2.0** in `scripts/setup-check.sh`, `README.md`, `docs/OVERVIEW.md`, `docs/ARCHITECTURE.md`. The `instance` / `switch` CLI vocabulary from 1.x is replaced by `env|environment` + `workspace pin-instance` in 2.x — all docs updated.
- **`marketplace.json` + `plugin.json`** synced to `3.6.0`.
- **`scripts/check-schema-versions.sh`** no longer calls `check-installed-nodes.sh` at the end (duplicate-fire per SessionStart). `setup-check.sh` Section 7 remains the sole caller.
- **`build-workflow` skill**: removed duplicate `test-plan` call from Path A, fixed wrong tool name (`validate_workflow` → `validate_n8n_workflow`), pulled Phase 2 fully into English, integrated naming conventions inline.
- **`docs/ARCHITECTURE.md`** rewritten to reflect the post-3.5 architecture (sole n8nac backend, no Native Instance MCP).

### Removed
- **Orphan files** — `skills/build-workflow/NAMING.md` (content folded into `build-workflow` Phase 1) and `skills/n8n-validation-expert/VALIDATION_RULES.md` (content folded into `n8n-validation-expert` body; the file's unused `paths:` frontmatter was a no-op).

### Renamed
- **`scripts/ensure-mcp-available.sh` → `scripts/ensure-mcp-trigger-setting.sh`** — the script guards the workflow setting `availableInMCP`, not MCP server reachability. Docs + hook reference updated.

## [3.5.x] — internal, not released to marketplace

3.5.0 introduced the `init-repo` skill and the inventory-freshness check. Marketplace was still pinned to 3.4.0; the 3.5.x line is rolled into 3.6.0 for the public release.

## [3.4.0] — 2026-04-13

### Removed
- **Native Instance MCP (16-Tool-SDK)** — the prior "Drei-Säulen-Architektur" (n8nac + Native Instance MCP + Plugin) collapsed to two pillars. n8nac is now the sole backend for all instance operations. All references in `docs/ARCHITECTURE.md` and `docs/OVERVIEW.md` removed.

### Changed
- **Adapted to n8nac 1.8.1** — structured JSON flags (`--strict --json`), min-version bump.

### Added
- **`check-credential-freshness.sh`** SessionStart hook.
- **`scripts/check-installed-nodes.sh`** — detects community nodes installed on the instance but missing from the local schema cache.
- **`ensure-mcp-available.sh`** PreToolUse hook — auto-guards the workflow setting `availableInMCP` for `mcpTrigger` pushes.

## [3.2.0 – 3.3.x] — community-node staleness + execution mandate

- Auto-fetch missing community node schemas + staleness detection.
- `execute/test` made mandatory in `build-workflow`; mcpTrigger publish lifecycle documented.

## [3.1.0]

- Upgraded n8nac to 1.5.5.

## [3.0.0]

- Integrated `n8n-instance` MCP as Tier-2 enrichment layer (5 → 16 tools). Later removed in 3.4.0.

---

For commit-level detail, see `git log` on `main`.
