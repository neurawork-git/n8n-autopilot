# Changelog

All notable changes to **n8n-autopilot** are documented here. Versions follow [Semantic Versioning](https://semver.org/).

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
