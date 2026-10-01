---
name: n8nac-cheatsheet
description: 'Curated "user intent → exact command" mapping for the n8nac CLI. Use this BEFORE reading `n8nac-reference` or running `--help`. Covers the 60+ common workflows — lookup, deploy, test, debug, migrate, credentials, projects, environments. If your task matches a row here, run the linked command verbatim — no flag fishing.'
allowed-tools: Read, Grep
---

# n8nac Cheat-Sheet

**Source-of-truth for "what command do I run for X?"** If your task matches a row, run the exact command shown — do not paraphrase, do not invent flags, do not run `--help`. If no row matches, fall back to `n8nac-reference` for the full help tree.

> All commands below assume `npx n8nac …` and a workspace bound to an n8n instance (`workspace status: bound`). Replace `<id>`, `<name>`, `<path>` with concrete values.

---

## Workspace & Setup

| User intent | Command |
|---|---|
| First-time setup (connect to existing n8n) | `npx n8nac env add <name> --base-url "$N8N_API_URL" --workflows-path workflows` then `printf "%s" "$N8N_API_KEY" \| npx n8nac env auth set <name> --api-key-stdin` then `npx n8nac env use <name>` |
| List supported setup modes | `npx n8nac setup-modes` |
| Show effective workspace context (active project, instance, sync folder) | `npx n8nac workspace status --json` |
| Bind instance + set sync folder (new env) | `npx n8nac env add <name> --base-url <url> --workflows-path workflows` |
| Switch active project on an environment | `npx n8nac env update <env> --project-name "<name>"` or `--project-id "<id>"` |
| Set workflow sync folder on an existing env | `npx n8nac env update <env> --workflows-path <relativePath>` |

## Multi-Environment (multiple n8n instances per repo)

| User intent | Command |
|---|---|
| List configured environments | `npx n8nac env list --json` |
| Show active environment + auth state | `npx n8nac env status --json` |
| Add a new environment | `npx n8nac env add <name> --base-url <url> --workflows-path workflows` |
| Switch active environment | `npx n8nac env use <name>` (alias: `env pin`) |
| Store API key for an environment | `printf "%s" "$N8N_API_KEY" \| npx n8nac env auth set <name> --api-key-stdin` |
| Remove the stored API key of ONE environment (n8nac ≥ 2.5) | `npx n8nac env auth clear <name>` |
| Update any env property (URL / project / sync folder / name) | `npx n8nac env update <name-or-id> --base-url <url>` (swap flag as needed) |
| Target one command at a non-active env | `npx n8nac --env <name> <command>` (root flag) |

## Workflows — Local & Remote Lifecycle

| User intent | Command |
|---|---|
| List all workflows (local + remote, excluding archived) | `npx n8nac list --json` |
| List including archived | `npx n8nac list --include-archived --json` |
| List archived only | `npx n8nac list --only-archived --json` |
| Filter by search term | `npx n8nac list --search "<query>" --json` |
| Search by partial name / ID / filename | `npx n8nac find "<query>" --json` |
| Search remote only | `npx n8nac find "<query>" --json --remote` |
| Download a single workflow from n8n | `npx n8nac pull <workflowId>` |
| Refresh internal cache for one workflow (no file write) | `npx n8nac fetch <workflowId>` |
| Upload a single workflow | `npx n8nac push <path>` |
| Upload + verify remote after push (preferred) | `npx n8nac push <path> --verify` |
| Validate remote workflow against local schema | `npx n8nac verify <workflowId>` |
| Resolve a local/remote conflict — remote wins | `npx n8nac pull <workflowId>` |
| Resolve a conflict — local wins (BLOCKED by push-gate) | `N8N_AUTOPILOT_ALLOW_LOCAL_WINS=1 npx n8nac resolve <id> --mode keep-current` |
| Resolve interactively | `npx n8nac resolve <id>` |
| Activate a workflow on the remote | `npx n8nac workflow activate <id>` |
| Deactivate a workflow | `npx n8nac workflow deactivate <id>` |
| Resolve the canonical UI URL | `npx n8nac workflow present <id> --json` |
| Check whether all credentials are present for a workflow | `npx n8nac workflow credential-required <id>` (exit 0 = OK, exit 1 = missing) |
| Promote a workflow from env A to env B | `npx n8nac promote <path> --from <envA> --to <envB>` |
| Convert local file JSON ↔ TypeScript | `npx n8nac convert <file>` |
| Batch convert a directory | `npx n8nac convert-batch <directory>` |
| Regenerate AGENTS.md + AI context | `npx n8nac update-ai` |

## Testing & Execution

| User intent | Command |
|---|---|
| Infer trigger type + payload before testing | `npx n8nac test-plan <id> --json` |
| Test webhook/chat/form (POST body) | `npx n8nac test <id> --data '<json>'` |
| Test webhook (GET query string) | `npx n8nac test <id> --query '<json>'` |
| Test against production URL (workflow must be active) | `npx n8nac test <id> --prod --data '<json>'` |
| Push WITHOUT releasing to production (2.6+; `push` otherwise publishes the running version) | `npx n8nac push <file> --draft` |
| List recent executions for a workflow | `npx n8nac execution list --workflow-id <id> --limit 10` |
| Get one execution's full I/O | `npx n8nac execution get <executionId> --include-data` |
| Get one execution's metadata only | `npx n8nac execution get <executionId>` |

## Credentials (direct CRUD)

| User intent | Command |
|---|---|
| List all credentials (metadata, no secrets) | `npx n8nac credential list --json` |
| Get one credential's metadata | `npx n8nac credential get <id>` |
| Show JSON schema for a credential type | `npx n8nac credential schema <type>` |
| Create a credential | `npx n8nac credential create --type <type> --name "<name>" --file cred.json` |
| Delete a credential | `npx n8nac credential delete <id>` |
| Change a credential value | **no `update` subcommand exists** — `credential delete` + `create`, then rewrite the id in every referencing `.workflow.ts` |

> **For project-aware credential lookup**, use `/n8n-autopilot:find-credential` (default = active project, no cross-project leak). Use `credential list` directly only when you need raw shape.

### Recipe: `oAuth2Api` with the client-credentials grant (machine-to-machine, no login)

The `oAuth2Api` schema is a nest of `if/then` branches and the validator demands fields from branches
that do not apply to your grant — guessing costs ~6 round trips. Working body (Microsoft Graph
app-only shown; same shape for any client-credentials provider):

```json
{
  "grantType": "clientCredentials",
  "serverUrl": "",
  "accessTokenUrl": "https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token",
  "clientId": "<app-id>",
  "clientSecret": "<secret>",
  "scope": "https://graph.microsoft.com/.default",
  "authentication": "body",
  "sendAdditionalBodyProperties": false,
  "additionalBodyProperties": {},
  "jweEnabled": false
}
```

**Run `npx n8nac credential schema oAuth2Api` first and use ONLY the keys it lists** — the field set
moves between n8n versions. Two traps:

- **`allowedHttpRequestDomains` exists only on some n8n versions.** On n8n ≥ 2.20 the schema
  rejects it as an additional property (HTTP 400, #89); on versions that have it, it is an enum
  (`all` / `domains` / `none`), not a boolean, and `"none"` passes validation and then fails at
  RUNTIME with *"This credential is configured to prevent use within an HTTP Request node"*. Add it
  only when `credential schema` lists it, and then as `"all"` (or `"domains"` + a list). Since there
  is no `update`, a wrong value means delete + recreate.
- **`additionalBodyProperties` is type `json`** — pass `{}`, not `""`.

Client-credentials needs **no** Connect button and no browser: the token is fetched server-side. If a
credential seems to require a login, you picked the delegated `authorizationCode` flow by mistake —
and a delegated Graph credential only sees what its user sees (the usual cause of a 403 on
tenant-wide reads).

## Credentials (recipes / readiness)

| User intent | Command |
|---|---|
| List available credential recipes (openai-native, slack-oauth, postgres, …) | `npx n8nac credentials recipes --json` |
| List the local credential inventory (which recipes are satisfied?) | `npx n8nac credentials inventory --json` |
| Create a credential from a recipe | `npx n8nac credentials ensure <recipeId>` |
| Test that a credential works against the live service | `npx n8nac credentials test <id-or-recipeId>` |
| List bundled starter-kits | `npx n8nac credentials starter-kits` |
| Apply a starter-kit | `npx n8nac credentials starter-kit <kitId>` |
| Delete a credential via the recipe surface | `npx n8nac credentials delete <id>` |

## Schemas, Node Info, Authoring Help

| User intent | Command |
|---|---|
| Search nodes by service / keyword | `npx n8nac skills search "<query>" --json` |
| Get exact TypeScript snippet for one node | `npx n8nac skills node-schema <type> --json` |
| Get full node info (params, credentials, typeVersion) | `npx n8nac skills node-info <type> --json` |
| Find related/alternative nodes | `npx n8nac skills related "<query>" --json` |
| Search community workflow examples (7000+ templates) | `npx n8nac skills examples search "<query>" --json` |
| Get details for one example | `npx n8nac skills examples info <id>` |
| Download an example as starting point | `npx n8nac skills examples download <id>` |
| Search docs / guides | `npx n8nac skills docs "<query>"` / `npx n8nac skills guides "<query>"` |
| Validate a `.workflow.ts` locally | `npx n8nac skills validate <path> --strict --json` |
| Refresh AI context (AGENTS.md etc.) via skills facade | `npx n8nac skills update-ai` |
| Launch n8nac's bundled MCP server (experimental) | `npx n8nac skills mcp` |
| Several node-info/search lookups in ONE process (2.6+; saves ~1 npx start per call) | `npx n8nac skills batch --calls-file calls.json --compact --json` (calls = `[{"cmd":"search","query":"gmail"},{"cmd":"node-info","name":"gmailTool"}]`) |
| Token-light node contract (identity + required params + snippet) | `npx n8nac skills node-info <type> --compact` |

## Native n8n MCP assist (ab n8nac 2.4 — read-only Broker gegen den Instanz-MCP)

| User intent | Command |
|---|---|
| Native MCP assist für ein Env konfigurieren (Token aus n8n UI → Settings → MCP) | `npx n8nac native-mcp configure <env> --token-stdin` (URL wird aus Env-Base-URL abgeleitet) |
| Verbindung/Konfiguration prüfen | `npx n8nac native-mcp doctor <env> --json` |
| Welche nativen Tools exposed die Instanz? | `npx n8nac native-mcp tools <env> --json` |
| Assist-Status inkl. Tools | `npx n8nac native-mcp status <env> --include-tools --json` |
| Assist abschalten | `npx n8nac native-mcp disable <env>` |

> Wrapper sind read-only (Discovery, Execution-Inspektion, Server-side Validation). Authoring bleibt
> `.workflow.ts` + `push`; Live-Tests bleiben `n8nac test`; Binär-Payloads NIE via MCP. Details +
> Test-Pfad-Evaluation: `docs/MCP.md`.

## Telemetry

| User intent | Command |
|---|---|
| Enable / disable / status anonymous telemetry | `npx n8nac telemetry --help` (small surface — read directly) |

---

## Common gotchas (always check these first)

1. **Singular vs. plural `credential` / `credentials`** — different parent groups. `credential` for raw CRUD on the active instance; `credentials` for recipes, inventory, starter-kits, and ensure/test against a recipe ID.
2. **`workspace status --json` returns two shapes**: bound (has `activeEnvironment` block) or pending (has `status: "dry-run"|"migration-required"`). Probe `j.activeEnvironment` first.
3. **Multi-project visibility**: `credential list --json` returns every credential the API key can see across ALL projects. Each cred carries `shared[]` with project ownership; use `/n8n-autopilot:find-credential` for project-scoped lookup instead of grep-piping.
4. **`push` blocked when status is `CONFLICT` / `MODIFIED_BOTH` / `DIVERGED` / `REMOTE_ONLY`** — see CLAUDE.md "Push-Gate" section. Bypass: `N8N_AUTOPILOT_ALLOW_LOCAL_WINS=1`.
5. **`resolve --mode keep-current` is unconditionally blocked** by the push-gate. Same bypass as above.
6. **`n8nac test` cannot trigger schedule/manual/errorTrigger** — only webhook/chat/form. For other triggers, prompt the user to "Execute Workflow" in the n8n UI (see `build-workflow` Path B).
7. **`mcpTrigger` workflows require manual UI publish** after every push. `n8nac push` writes a new draft; the previously-published MCP endpoint may diverge.
8. **Archived workflows are read-only**. `push` will reject. Unarchive in n8n UI first (no n8nac command for this).
9. **Curl carve-out**: `/api/v1/data-tables` is the only n8n public API path you may hit directly (see `/n8n-autopilot:data-tables`). Everything else goes through `n8nac`.
10. **Old commands removed in n8nac >= 2.3**: `init`, `init-auth`, `init-project` no longer exist — use `setup --mode <mode>`. Post-setup binding is via `env add` / `env auth set` / `env use` (NOT `workspace pin-instance`, which is also removed). `workspace set-project`, `workspace set-sync-folder`, `workspace clear-*`, `workspace migrate`, `workspace migrate-v1`, and `instance-target` are all gone — use `env update <name> --project-name/--workflows-path` instead.

## When this cheat-sheet is not enough

Read [`n8nac-reference/reference.md`](../n8nac-reference/reference.md) — the full machine-generated help tree (61 command/subcommand blocks).
