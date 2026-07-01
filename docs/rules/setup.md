# Setup — n8n-autopilot + companion plugin

**Brand-new repo? One command:**
→ `/n8n-autopilot:init-repo [target-dir]` — scaffolds dir layout + CLAUDE.md / README /
`.gitignore` / `.mcp.json` / `.env.example`, runs the v2.3 setup flow (`env add` + `env auth set`
+ `env use`), pulls schemas, verifies.

## Manual (if you prefer step-by-step)

1. Install both plugins (n8n-autopilot + Etienne's companion):
   ```bash
   claude plugin marketplace add neurawork-git/n8n-autopilot
   claude plugin install n8n-autopilot@n8n-autopilot

   claude plugin marketplace add EtienneLescot/n8n-as-code
   claude plugin install n8n-as-code@n8nac-marketplace
   ```
   The companion plugin (Etienne) provides the `n8n-architect` skill that owns schema-research,
   authoring rules, AI/LangChain rules, etc. n8n-autopilot does workflow lifecycle orchestration
   (init-repo, build-workflow pipeline, deploy, sync-credentials, inventory, data-tables).
2. Add and activate the environment (n8nac >= 2.3 stores config in user home, NOT the repo):
   ```bash
   npx n8nac env add Prod --base-url "$N8N_API_URL" --workflows-path workflows
   printf '%s' "$N8N_API_KEY" | npx n8nac env auth set Prod --api-key-stdin
   npx n8nac env use Prod
   # Optional, for multi-project instances:
   npx n8nac env update Prod --project-name Personal
   ```
3. `/n8n-autopilot:pull-schemas` — populate `schemas/nodes/` (gitignored, instance-specific)
4. Verify: `/n8n-autopilot:check-mcps` (or runs auto via SessionStart hook; expects workspace
   status `bound`)

## Legacy in-repo config

**Stray in-repo `./n8nac-config.json`?** The `workspace migrate` / `migrate-v1` commands no longer
exist — workspace storage is v4-native (config lives in `~/n8nac-config.json` + `~/.n8n-manager/`).
If a legacy in-repo config file exists, **delete it manually** — there is no migration command.
(The SessionStart probe `scripts/check-workspace-migration.sh` only warns; it cannot auto-fix.)

## Reference n8nac version

**2.3.6** (minimum 2.3.0). All setup/credential flows target the v4-native environment-centric
config model. Single source of truth: `REFERENCE_N8NAC_VERSION` constant in `scripts/setup-check.sh`.
Bump procedure: update the constant, sync README badges + `plugin.json`, add a CHANGELOG entry.
