# Testing — through the instance's own MCP server

Since 5.4.0 the build pipelines ask the n8n instance itself to run a workflow instead of firing its
URL from outside. One token serves both halves:

| Half | Uses | What it does |
|---|---|---|
| **Push check** | `scripts/instance-node-check.mjs` in the push-lint gate | The push-lint gate asks the instance's `get_node_types` whether every node type and `typeVersion` exists there, and blocks the push when one does not. (`param-version-check.py` then checks, offline, that every parameter exists for that version — [gates.md](gates.md).) |
| **Test execution** | the plugin's MCP server `n8n-native` | The `n8n-tester` agent runs the pushed draft: pinned by default (`prepare_test_pin_data` → `test_workflow`), live only with real caller data (`execute_workflow`, manual mode). |

Both resolve the SESSION env (`N8NAC_ENVIRONMENT`) through n8nac's config API and talk to that
env's `https://<instance>/mcp-server/http` with the token n8nac stored for it
(`scripts/lib/native-mcp.mjs`). A customer repo pinned to its env therefore reaches its own
instance; with no pin, both refuse instead of guessing. Verified live on 2026-09-22 against the internal
instance: a schedule-trigger workflow ran headless and inactive through both `execute_workflow` and
`test_workflow`.

## Two test modes

| Mode | When | Tools | Side effects |
|---|---|---|---|
| **Pinned** (default) | always, unless the caller passes real test data | `prepare_test_pin_data` → `test_workflow` → `get_execution` | none — triggers, credentialed nodes and HTTP Request nodes run on pin data; Set/If/Code/etc. execute for real |
| **Live** | caller passes `testData`, trigger is webhook / form / chat / schedule / manual | `execute_workflow` (`executionMode: "manual"` = pushed draft) → poll `get_execution` | real — mails are sent, rows written |

`prepare_test_pin_data` returns a JSON schema per node that needs pin data, derived from past
executions or the node definition. The tester fills them with sample items. Every item must be
wrapped as `{"json": {...}}`; flat objects are rejected. `test_workflow` waits for the run and
returns `{executionId, status}`. `execute_workflow` returns at once and has to be polled.

## Why not `n8nac test` any more

| Problem with the URL path | Native MCP |
|---|---|
| Only webhook / chat / form triggers can be fired. Schedule and manual triggers needed a human in the UI (#10, #72). | Pinned tests start from any trigger. |
| The test webhook must be armed in the editor, so the pipeline activated the workflow to hit the production URL. Activation changed the remote hash and created drift the push-gate then blocked (#37). | Both modes run the pushed draft. Nothing is activated. |
| Form triggers got a JSON POST to the form URL and answered with the form page (#59, #91). Arrays as bodies were refused (#71). | Pin data per node; live inputs are typed (`formData`, `chatInput`, `webhookData`). |
| Synthetic payloads hit real services and failed on placeholder ids (`test-data-gap`). | Pinned mode never calls the service. |

## Setup — once per environment

The plugin ships `n8n-native` (declared in `.claude-plugin/plugin.json`, runs
`scripts/n8n-native-proxy.mjs`). There is nothing to register in Claude Code. Per environment:

1. **Create the token.** n8n UI → Settings → MCP → enable the server → create an access token.
   Store it in the customer's Infisical project (internal instances: `thecluster`).
2. **Hand it to n8nac** — in your own terminal, so the token never passes through the chat.
   `--token-stdin` reads from a **pipe**; run bare, it waits silently forever.

   ```powershell
   $t = Read-Host "n8n MCP Token" -MaskInput
   $t | npx n8nac native-mcp configure <env> --token-stdin --level 2
   Remove-Variable t
   ```

   ```bash
   read -rs -p "n8n MCP Token: " t; echo
   printf '%s' "$t" | npx n8nac native-mcp configure <env> --token-stdin --level 2
   unset t
   ```

3. **Verify:** `N8NAC_ENVIRONMENT=<env> node scripts/check-native-mcp.mjs --live` → `✅ native MCP ready`.
   The SessionStart probe runs the offline half of this every session and prints the remedy when
   the pinned env is not configured. `/n8n-autopilot:init-repo` (step 4b) and
   `/n8n-autopilot:check-mcps` (step 4b) include it.
4. **Per workflow:** `settings.availableInMCP: true` in the `@workflow` decorator. n8n refuses MCP
   access to a workflow without it, and the push-lint gate blocks the push.

## n8nac 2.7.0 traps found while wiring this

- **`native-mcp status` / `doctor` report "disabled" from a repo directory.** They resolve the config
  only in the current directory and swallow the error, while the other commands walk up to the
  `n8nac-config.json` (here `C:\Users\neura`). Pass `--cwd <dir of n8nac-config.json>`:
  `npx n8nac native-mcp status n8n-autopilot-tester --cwd C:\Users\neura --include-tools --json`.
- **Level 2 push validation is a no-op on this instance.** It needs the instance tool
  `validate_node_config`, which the instance does not expose. n8nac then prints "Instance node
  validation unavailable … validated against the bundled schema" and pushes anyway. That is why
  the gate runs `instance-node-check.mjs` itself.
- **The instance node catalogue is incomplete.** `get_node_types` answers "not found" for hidden
  (deprecated) core nodes and for some installed community nodes (PandaDoc: "not found", yet it
  executed on the instance the same day; Apify: found). The gate therefore enforces core packages
  only and reports community nodes as warnings.
- **The n8nac MCP broker cannot check a version.** `get_n8n_native_node_types` sends `version` as a
  number and the instance rejects it (`-32602`). `instance-node-check.mjs` talks to the instance
  directly, using the endpoint and token n8nac stored for the env.

## Guard rails

- **Only test and read tools are exposed.** `n8n-native` forwards `prepare_test_pin_data`,
  `test_workflow`, `execute_workflow`, `get_execution`, `get_workflow_details`, `search_workflows`,
  `get_node_types`, `search_nodes`. The instance's write tools (`create_workflow_from_code`,
  `update_workflow`, `archive_workflow`, `publish_workflow`, data-table writes) are not reachable.
  Workflows change through the `.workflow.ts` file and `npx n8nac push`; a direct write would create
  drift the push-gate cannot see.
- **Every tool description names the target.** `[instance https://… · env …]` — check it before a
  live `execute_workflow`.
- **One path, no fallback.** When the MCP call fails, the tester reports `mcp-unavailable` with the
  server's message and the build fails with the setup hint. It does not quietly switch back to
  `n8nac test`.
- **The token sees the whole instance.** `search_workflows` returned all 272 workflows, not only the
  pinned project. Treat it like an admin credential; it lives only in n8nac's secret store.

## What is still manual

- **`mcpTrigger` workflows** need the Publish click in the n8n UI after every push
  ([manual-detours](../troubleshooting/manual-detours.md)).
