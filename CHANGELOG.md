# Changelog

All notable changes to **n8n-autopilot** are documented here. Versions follow [Semantic Versioning](https://semver.org/).

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

Verified end-to-end against Falkensteg/: pull-schemas pulled 16 core schemas, inventory rendered the report, sync-credentials --fix-workflows --dry-run correctly detected 16 stale credential references plus 5 orphans.

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
