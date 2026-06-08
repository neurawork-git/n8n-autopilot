# n8nac CLI Reference — Generated

Generated automatically from `n8nac --help` recursion. n8nac version: **2.3.6**.

This file is the source of truth for what subcommands and flags exist. If a command appears here, it exists. If it does not appear here, **it does not exist** — do not invent it.

To regenerate after an n8nac upgrade:

```bash
bash scripts/dump-n8nac-help.sh > skills/n8nac-reference/reference.md
```

---

## Root

```
Usage: n8nac [options] [command]

N8N Sync Command Line Interface - Manage n8n workflows as code

Options:
  -V, --version                        output the version number
  --env <name>                         Target a specific workspace environment
                                       by name or ID
  -h, --help                           display help for command

Commands:
  telemetry                            Manage anonymous n8n-as-code telemetry
  workspace                            Inspect n8n workspace configuration
  env|environment                      Manage n8n workspace environments
  setup [options]                      Choose how this facade should use n8n
                                       runtime capabilities
  setup-modes [options]                List supported facade setup modes
  credentials                          Manage credential readiness recipes and
                                       local inventory
  list [options]                       Display a table of all workflows and
                                       their current status (local, remote, or
                                       both). By default, only non-archived
                                       workflows are shown.
  find [options] <query>               Find workflows quickly by partial name,
                                       workflow ID, or local filename. By
                                       default, only non-archived workflows are
                                       searched.
  pull <workflowId>                    Download a single workflow from n8n to
                                       local directory
  push [options] <path>                Upload a single local workflow to n8n
  promote [options] [path]             Promote a local workflow file from one
                                       workspace environment to another
  verify <workflowId>                  Fetch a workflow from n8n and validate
                                       its nodes against the local schema
                                       (detects invalid typeVersion, bad
                                       operation values, missing required
                                       params)
  test [options] <workflowId>          Trigger a workflow via its
                                       webhook/chat/form URL and report the
                                       outcome.
                                       Distinguishes config gaps (Class A:
                                       missing credentials/model), runtime
                                       state issues
                                       (test webhook not armed / production
                                       webhook not registered), and wiring
                                       errors
                                       (Class B: bad expressions, wrong field
                                       names).
                                       Class A → exit 0 (inform user, do not
                                       block).
                                       Runtime state issue → exit 0 (do not
                                       edit code blindly).
                                       Class B → exit 1 (fixable, agent should
                                       iterate).
  test-plan [options] <workflowId>     Inspect how a workflow can be tested via
                                       HTTP and infer a suggested payload
  fetch <workflowId>                   Fetch remote state for a specific
                                       workflow (update internal cache for
                                       comparison)
  resolve [options] <workflowId>       Resolve a conflict for a specific
                                       workflow
  convert [options] <file>             Convert workflows between JSON and
                                       TypeScript formats
  convert-batch [options] <directory>  Batch convert all workflows in a
                                       directory
  mcp [options]                        Start the dedicated n8n-as-code MCP
                                       server
  workflow                             Workflow lifecycle management (present,
                                       activate, deactivate, inspect
                                       credentials)
  execution                            Inspect workflow executions for
                                       debugging and post-run diagnosis
  credential                           Manage credentials in the active n8n
                                       environment
  skills                               AI tools: search nodes, docs, guides,
                                       validate workflows, and more
  update-ai [options]                  Update AI Context (AGENTS.md and
                                       snippets)
  help [command]                       display help for command
```

---

## `n8nac telemetry`

### `n8nac telemetry`

```
Usage: n8nac telemetry [options] [command]

Manage anonymous n8n-as-code telemetry

Options:
  -h, --help         display help for command

Commands:
  status [options]   Show anonymous telemetry status
  enable [options]   Enable anonymous telemetry
  disable [options]  Disable anonymous telemetry
  help [command]     display help for command
```

---

## `n8nac workspace`

### `n8nac workspace`

```
Usage: n8nac workspace [options] [command]

Inspect n8n workspace configuration

Options:
  -h, --help            display help for command

Commands:
  status|get [options]  Show the effective n8n workspace context resolved by
                        the backend
  help [command]        display help for command
```

### `n8nac workspace status`

```
Usage: n8nac workspace status|get [options]

Show the effective n8n workspace context resolved by the backend

Options:
  --json      Output effective workspace context as JSON
  -h, --help  display help for command
```

---

## `n8nac env`

### `n8nac env`

```
Usage: n8nac env|environment [options] [command]

Manage n8n workspace environments

Options:
  -h, --help                        display help for command

Commands:
  list [options]                    List workspace environments
  add [options] <name>              Add an n8n workspace environment
  update [options] <name-or-id>     Update a workspace environment
  pin|use [options] <name-or-id>    Pin the default workspace environment
  remove|rm [options] <name-or-id>  Remove a workspace environment
  auth                              Manage local authentication for n8n
                                    environments
  status [options] [name-or-id]     Show resolved workspace environment context
  help [command]                    display help for command
```

### `n8nac env add`

```
Usage: n8nac env add [options] <name>

Add an n8n workspace environment

Arguments:
  name                        Environment display name

Options:
  --base-url <url>            Remote n8n URL to store in this workspace
                              environment
  --managed-instance <id>     Local managed n8n instance ID to reference
  --api-key <key>             Store a local API key for --base-url without
                              committing it
  --api-key-stdin             Read the local API key for --base-url from stdin
  --project-id <id>           n8n project ID
  --project-name <name>       n8n project display name
  --workflows-path <path>     Directory that contains this environment
                              workflows
  --id <id>                   Stable environment ID
  --folder-sync               Enable folder sync for this environment
  --custom-nodes-path <path>  Custom nodes path for this environment
  --description <text>        Environment description
  --json                      Output environment as JSON
  -h, --help                  display help for command
```

### `n8nac env auth`

```
Usage: n8nac env auth [options] [command]

Manage local authentication for n8n environments

Options:
  -h, --help                  display help for command

Commands:
  set [options] <name-or-id>  Store a local API key for a remote n8n
                              environment without committing it
  help [command]              display help for command
```

### `n8nac env list`

```
Usage: n8nac env list [options]

List workspace environments

Options:
  --json      Output environments as JSON
  -h, --help  display help for command
```

### `n8nac env pin`

```
Usage: n8nac env pin|use [options] <name-or-id>

Pin the default workspace environment

Arguments:
  name-or-id  Environment name or ID

Options:
  --json      Output environment as JSON
  -h, --help  display help for command
```

### `n8nac env remove`

```
Usage: n8nac env remove|rm [options] <name-or-id>

Remove a workspace environment

Arguments:
  name-or-id  Environment name or ID

Options:
  --force     Remove the active environment and clear the active environment
              pin
  --json      Output removed environment as JSON
  -h, --help  display help for command
```

### `n8nac env status`

```
Usage: n8nac env status [options] [name-or-id]

Show resolved workspace environment context

Arguments:
  name-or-id  Environment name or ID; defaults to pinned environment or --env

Options:
  --json      Output resolved environment as JSON
  -h, --help  display help for command
```

### `n8nac env update`

```
Usage: n8nac env update [options] <name-or-id>

Update a workspace environment

Arguments:
  name-or-id                  Environment name or ID

Options:
  --name <name>               New display name
  --base-url <url>            Move this environment to a remote n8n URL
  --managed-instance <id>     Move this environment to a local managed n8n
                              instance
  --api-key <key>             Store a local API key for --base-url without
                              committing it
  --api-key-stdin             Read the local API key for --base-url from stdin
  --project-id <id>           n8n project ID
  --project-name <name>       n8n project display name
  --workflows-path <path>     Directory that contains this environment
                              workflows
  --folder-sync               Enable folder sync for this environment
  --no-folder-sync            Disable folder sync for this environment
  --custom-nodes-path <path>  Custom nodes path for this environment
  --description <text>        Environment description
  --json                      Output environment as JSON
  -h, --help                  display help for command
```

---

## `n8nac setup`

### `n8nac setup`

```
Usage: n8nac setup [options]

Choose how this facade should use n8n runtime capabilities

Options:
  --mode <mode>      managed-local, connect-existing, or generation-only
                     (default: "connect-existing")
  --host <url>       Existing n8n URL for connect-existing mode
  --api-key <key>    Existing n8n API key for active credential operations
  --api-key-stdin    Read the n8n API key from stdin
  --project-id <id>  n8n project ID for credential operations
  --json             Output setup result as JSON
  -h, --help         display help for command
```

---

## `n8nac setup-modes`

### `n8nac setup-modes`

```
Usage: n8nac setup-modes [options]

List supported facade setup modes

Options:
  --json      Output modes as JSON
  -h, --help  display help for command
```

---

## `n8nac credentials`

### `n8nac credentials`

```
Usage: n8nac credentials [options] [command]

Manage credential readiness recipes and local inventory

Options:
  -h, --help                                 display help for command

Commands:
  recipes [options]                          List credential recipes available to all facades
  starter-kits [options]                     List starter credential kits
  inventory [options]                        Show local credential readiness inventory
  ensure [options] <recipeId>                Create or mark a credential from a shared recipe
  starter-kit [options] <starterKitId>       Bootstrap a shared starter credential kit
  test [options] <credentialIdOrRecipeId>    Test a credential by n8n credential ID or recipe ID
  delete [options] <credentialIdOrRecipeId>  Delete a credential by n8n credential ID or shared recipe ID
  help [command]                             display help for command
```

### `n8nac credentials delete`

```
Usage: n8nac credentials delete [options] <credentialIdOrRecipeId>

Delete a credential by n8n credential ID or shared recipe ID

Arguments:
  credentialIdOrRecipeId  Credential ID or recipe ID

Options:
  --host <url>            n8n URL for real credential deletion
  --api-key <key>         n8n API key for real credential deletion
  --api-key-stdin         Read the n8n API key from stdin
  --project-id <id>       n8n project ID
  --json                  Output delete result as JSON
  -h, --help              display help for command
```

### `n8nac credentials ensure`

```
Usage: n8nac credentials ensure [options] <recipeId>

Create or mark a credential from a shared recipe

Arguments:
  recipeId                Credential recipe ID

Options:
  --host <url>            n8n URL for real credential creation
  --api-key <key>         n8n API key for real credential creation
  --api-key-stdin         Read the n8n API key from stdin
  --project-id <id>       n8n project ID
  --name <name>           Credential name
  --value <key=value...>  Credential input value
  --json                  Output credential ref as JSON
  -h, --help              display help for command
```

### `n8nac credentials inventory`

```
Usage: n8nac credentials inventory [options]

Show local credential readiness inventory

Options:
  --json      Output inventory as JSON
  -h, --help  display help for command
```

### `n8nac credentials recipes`

```
Usage: n8nac credentials recipes [options]

List credential recipes available to all facades

Options:
  --json      Output recipes as JSON
  -h, --help  display help for command
```

### `n8nac credentials starter-kit`

```
Usage: n8nac credentials starter-kit [options] <starterKitId>

Bootstrap a shared starter credential kit

Arguments:
  starterKitId       Starter kit ID

Options:
  --host <url>       n8n URL for real credential creation
  --api-key <key>    n8n API key for real credential creation
  --api-key-stdin    Read the n8n API key from stdin
  --project-id <id>  n8n project ID
  --json             Output starter kit result as JSON
  -h, --help         display help for command
```

### `n8nac credentials starter-kits`

```
Usage: n8nac credentials starter-kits [options]

List starter credential kits

Options:
  --json      Output starter kits as JSON
  -h, --help  display help for command
```

### `n8nac credentials test`

```
Usage: n8nac credentials test [options] <credentialIdOrRecipeId>

Test a credential by n8n credential ID or recipe ID

Arguments:
  credentialIdOrRecipeId  Credential ID or recipe ID

Options:
  --host <url>            n8n URL for real credential test
  --api-key <key>         n8n API key for real credential test
  --api-key-stdin         Read the n8n API key from stdin
  --project-id <id>       n8n project ID
  --json                  Output test result as JSON
  -h, --help              display help for command
```

---

## `n8nac list`

### `n8nac list`

```
Usage: n8nac list [options]

Display a table of all workflows and their current status (local, remote, or
both). By default, only non-archived workflows are shown.

Options:
  --local             Show only local workflows
  --remote            Show only remote workflows
  --distant           Alias for --remote
  --search <query>    Filter by workflow name, ID, or local filename
                      (case-insensitive partial match)
  --sort <mode>       Sort by "status" (default) or "name" (default: "status")
  --limit <number>    Limit the number of returned workflows
  --include-archived  Include archived workflows in the output
  --only-archived     Show only archived workflows
  --json              Output full JSON instead of a table
  -h, --help          display help for command
```

---

## `n8nac find`

### `n8nac find`

```
Usage: n8nac find [options] <query>

Find workflows quickly by partial name, workflow ID, or local filename. By
default, only non-archived workflows are searched.

Arguments:
  query               Search query

Options:
  --local             Show only local workflows
  --remote            Show only remote workflows
  --distant           Alias for --remote
  --sort <mode>       Sort by "status" or "name" (default: "name")
  --limit <number>    Limit the number of returned workflows
  --include-archived  Include archived workflows in the search
  --only-archived     Search only archived workflows
  --json              Output full JSON instead of a table
  -h, --help          display help for command
```

---

## `n8nac pull`

### `n8nac pull`

```
Usage: n8nac pull [options] <workflowId>

Download a single workflow from n8n to local directory

Arguments:
  workflowId  Workflow ID to pull

Options:
  -h, --help  display help for command
```

---

## `n8nac push`

### `n8nac push`

```
Usage: n8nac push [options] <path>

Upload a single local workflow to n8n

Arguments:
  path        Path to a local workflow file inside the active sync scope
              (absolute or relative)

Options:
  --verify    After pushing, fetch the workflow from n8n and validate it
              against the local schema
  -h, --help  display help for command
```

---

## `n8nac promote`

### `n8nac promote`

```
Usage: n8nac promote [options] [path]

Promote a local workflow file from one workspace environment to another

Arguments:
  path                       Workflow file path inside the source environment
                             workflowsPath. Omit to promote all source
                             workflows.

Options:
  --from <environment>       Source environment name or ID
  --to <environment>         Target environment name or ID
  --dry-run                  Show the planned promotion without writing or
                             pushing
  --no-push                  Copy/adapt the workflow into the target
                             environment without pushing
  --overwrite                Overwrite the target local workflow file if it
                             already exists
  --promotion-config <path>  Promotion config path (default:
                             "n8nac-promotion.json")
  --no-interactive           Disable interactive credential mapping prompts
  --json                     Output promotion result as JSON
  -h, --help                 display help for command
```

---

## `n8nac verify`

### `n8nac verify`

```
Usage: n8nac verify [options] <workflowId>

Fetch a workflow from n8n and validate its nodes against the local schema
(detects invalid typeVersion, bad operation values, missing required params)

Arguments:
  workflowId  Workflow ID to verify

Options:
  -h, --help  display help for command
```

---

## `n8nac test`

### `n8nac test`

```
Usage: n8nac test [options] <workflowId>

Trigger a workflow via its webhook/chat/form URL and report the outcome.
Distinguishes config gaps (Class A: missing credentials/model), runtime state
issues
(test webhook not armed / production webhook not registered), and wiring errors
(Class B: bad expressions, wrong field names).
Class A → exit 0 (inform user, do not block).
Runtime state issue → exit 0 (do not edit code blindly).
Class B → exit 1 (fixable, agent should iterate).

Arguments:
  workflowId      Workflow ID to test

Options:
  --prod          Call the production webhook URL instead of the test URL
  --data <json>   JSON body to send with the request (for GET/HEAD webhooks
                  this becomes query params unless --query is provided)
  --query <json>  JSON query parameters to send with the request (useful for
                  GET/HEAD webhooks)
  -h, --help      display help for command

Examples:
  $ n8nac test <workflowId>
  $ n8nac test <workflowId> --data '{"chatInput":"hello"}'
  $ n8nac test <workflowId> --prod --query '{"chatInput":"hello"}'

Notes:
  - For GET/HEAD webhooks, `--data` is sent as query parameters for backward compatibility.
  - Prefer `--query` when the workflow reads from `$json.query` to make the intent explicit.
  - For classic Webhook/Form test URLs, you may need to manually arm the workflow in the n8n editor before the test URL will accept a request.

```

---

## `n8nac test-plan`

### `n8nac test-plan`

```
Usage: n8nac test-plan [options] <workflowId>

Inspect how a workflow can be tested via HTTP and infer a suggested payload

Arguments:
  workflowId  Workflow ID to inspect

Options:
  --json      Output the test plan as JSON for agents and scripts
  -h, --help  display help for command
```

---

## `n8nac fetch`

### `n8nac fetch`

```
Usage: n8nac fetch [options] <workflowId>

Fetch remote state for a specific workflow (update internal cache for
comparison)

Arguments:
  workflowId  Workflow ID to fetch

Options:
  -h, --help  display help for command
```

---

## `n8nac resolve`

### `n8nac resolve`

```
Usage: n8nac resolve [options] <workflowId>

Resolve a conflict for a specific workflow

Arguments:
  workflowId     Workflow ID to resolve

Options:
  --mode <mode>  Resolution mode: "keep-current" (local) or "keep-incoming"
                 (remote)
  -h, --help     display help for command
```

---

## `n8nac convert`

### `n8nac convert`

```
Usage: n8nac convert [options] <file>

Convert workflows between JSON and TypeScript formats

Arguments:
  file                 Path to workflow file (.json or .workflow.ts)

Options:
  -o, --output <path>  Output file path
  -f, --force          Overwrite existing output file
  --format <format>    Target format: "json" or "typescript" (auto-detected if
                       not specified)
  -h, --help           display help for command
```

---

## `n8nac convert-batch`

### `n8nac convert-batch`

```
Usage: n8nac convert-batch [options] <directory>

Batch convert all workflows in a directory

Arguments:
  directory          Directory containing workflow files

Options:
  --format <format>  Target format: "json" or "typescript"
  -f, --force        Overwrite existing files
  -h, --help         display help for command
```

---

## `n8nac mcp`

### `n8nac mcp`

```
Usage: n8nac mcp [options]

Start the dedicated n8n-as-code MCP server

Options:
  --cwd <path>  Project directory used to resolve n8nac-config.json and
                n8nac-custom-nodes.json
  -h, --help    display help for command
```

---

## `n8nac workflow`

### `n8nac workflow`

```
Usage: n8nac workflow [options] [command]

Workflow lifecycle management (present, activate, deactivate, inspect
credentials)

Options:
  -h, --help                                  display help for command

Commands:
  present [options] <workflowId>              Resolve a user-facing workflow URL from the active n8nac environment
  activate <workflowId>                       Activate (publish) a workflow so it can be triggered
  deactivate <workflowId>                     Deactivate a workflow (stops triggers from firing)
  credential-required [options] <workflowId>  List credentials required by a workflow and whether they already exist.
  Exits 0 if all present, exits 1 if any are missing (agent-friendly).
  help [command]                              display help for command
```

### `n8nac workflow activate`

```
Usage: n8nac workflow activate [options] <workflowId>

Activate (publish) a workflow so it can be triggered

Arguments:
  workflowId  Workflow ID to activate

Options:
  -h, --help  display help for command
```

### `n8nac workflow credential-required`

```
Usage: n8nac workflow credential-required [options] <workflowId>

List credentials required by a workflow and whether they already exist.
Exits 0 if all present, exits 1 if any are missing (agent-friendly).

Arguments:
  workflowId  Workflow ID to inspect

Options:
  --json      Output as JSON array for agent/script consumption
  -h, --help  display help for command
```

### `n8nac workflow deactivate`

```
Usage: n8nac workflow deactivate [options] <workflowId>

Deactivate a workflow (stops triggers from firing)

Arguments:
  workflowId  Workflow ID to deactivate

Options:
  -h, --help  display help for command
```

### `n8nac workflow present`

```
Usage: n8nac workflow present [options] <workflowId>

Resolve a user-facing workflow URL from the active n8nac environment

Arguments:
  workflowId  Workflow ID to present

Options:
  --json      Output as JSON for agent/script consumption
  -h, --help  display help for command
```

---

## `n8nac execution`

### `n8nac execution`

```
Usage: n8nac execution [options] [command]

Inspect workflow executions for debugging and post-run diagnosis

Options:
  -h, --help          display help for command

Commands:
  list [options]      List executions, optionally filtered by workflow or
                      status
  get [options] <id>  Get a single execution by ID
  help [command]      display help for command
```

### `n8nac execution get`

```
Usage: n8nac execution get [options] <id>

Get a single execution by ID

Arguments:
  id              Execution ID

Options:
  --include-data  Include execution run data and workflow details
  --json          Output JSON (default behavior; accepted for script
                  compatibility)
  -h, --help      display help for command

Examples:
  $ n8nac execution get <executionId>
  $ n8nac execution get <executionId> --include-data --json

```

### `n8nac execution list`

```
Usage: n8nac execution list [options]

List executions, optionally filtered by workflow or status

Options:
  --workflow-id <id>  Workflow ID to filter executions by
  --status <status>   Status filter:
                      canceled|crashed|error|new|running|success|unknown|waiting
  --project-id <id>   Project ID to filter executions by
  --limit <number>    Limit the number of returned executions
  --cursor <cursor>   Pagination cursor from a previous execution list call
  --include-data      Include execution data in list results (large output,
                      usually use execution get instead)
  --json              Output JSON for agents and scripts
  -h, --help          display help for command

Examples:
  $ n8nac execution list --workflow-id <workflowId> --limit 5
  $ n8nac execution list --workflow-id <workflowId> --status error --json

```

---

## `n8nac credential`

### `n8nac credential`

```
Usage: n8nac credential [options] [command]

Manage credentials in the active n8n environment

Options:
  -h, --help               display help for command

Commands:
  schema [options] <type>  Show the JSON schema for a credential type — lists
                           required fields and their types
  list [options]           List all credentials (metadata only, no secrets)
  get [options] <id>       Get credential metadata by ID (no secrets returned)
  create [options]         Create a new credential
  delete <id>              Permanently delete a credential
  help [command]           display help for command
```

### `n8nac credential create`

```
Usage: n8nac credential create [options]

Create a new credential

Options:
  --type <type>      Credential type name (e.g. notionApi)
  --name <name>      Display name for the credential
  --data <json>      Credential data as inline JSON string (avoid for secrets —
                     use --file instead)
  --file <path>      Path to JSON file with credential data (preferred over
                     --data)
  --project-id <id>  Project to assign the credential to
  --json             Output created credential metadata as JSON
  -h, --help         display help for command

Examples:
  $ n8nac credential schema openAiApi
  $ n8nac credential create --type openAiApi --name "My OpenAI" --file cred.json
  $ n8nac credential create --type openAiApi --name "My OpenAI" --file cred.json --json

Notes:
  - Prefer --file over --data to keep secrets out of shell history.
  - Run 'n8nac credential schema <type>' before creating a new credential type.
  - If creation fails, read the returned validation message and change the payload before retrying.

```

### `n8nac credential delete`

```
Usage: n8nac credential delete [options] <id>

Permanently delete a credential

Arguments:
  id          Credential ID

Options:
  -h, --help  display help for command
```

### `n8nac credential get`

```
Usage: n8nac credential get [options] <id>

Get credential metadata by ID (no secrets returned)

Arguments:
  id          Credential ID

Options:
  --json      Output JSON (default behavior; accepted for script compatibility)
  -h, --help  display help for command
```

### `n8nac credential list`

```
Usage: n8nac credential list [options]

List all credentials (metadata only, no secrets)

Options:
  --json      Output the credential list as JSON for agents and scripts
  -h, --help  display help for command

Examples:
  $ n8nac credential list
  $ n8nac credential list --json

```

### `n8nac credential schema`

```
Usage: n8nac credential schema [options] <type>

Show the JSON schema for a credential type — lists required fields and their
types

Arguments:
  type        Credential type name (e.g. notionApi, slackOAuth2Api, googleApi)

Options:
  --json      Output JSON (default behavior; accepted for script compatibility)
  -h, --help  display help for command

Examples:
  $ n8nac credential schema openAiApi
  $ n8nac credential schema slackApi --json

```

---

## `n8nac skills`

### `n8nac skills`

```
Usage: n8nac skills [options] [command]

AI tools: search nodes, docs, guides, validate workflows, and more

Options:
  -h, --help                    display help for command

Commands:
  search [options] <query>      Search for n8n nodes and documentation
  list [options]                List available nodes, documentation categories,
                                or guides
  node-info [options] <name>    Get complete node information as TypeScript
                                code
  node-schema [options] <name>  Get TypeScript code snippet for a node (quick
                                reference)
  docs [options] [title]        Access n8n documentation pages
  guides [options] [query]      Find workflow guides, tutorials, and
                                walkthroughs
  related <query>               Find related nodes and documentation
  validate [options] <file>     Validate a workflow file (JSON or TypeScript)
  update-ai [options]           Update AI Context files (AGENTS.md)
  mcp [options]                 Compatibility redirect to `n8nac mcp`
  examples                      Search and download community workflows (7000+
                                from n8nworkflows.xyz)
  help [command]                display help for command
```

### `n8nac skills docs`

```
Usage: n8nac skills docs [options] [title]

Access n8n documentation pages

Arguments:
  title                  Documentation page title

Options:
  --list                 List all categories
  --category <category>  Filter by category
  -h, --help             display help for command
```

### `n8nac skills examples`

```
Usage: n8nac skills examples [options] [command]

Search and download community workflows (7000+ from n8nworkflows.xyz)

Options:
  -h, --help                display help for command

Commands:
  search [options] <query>  Search community workflows
  list [options]            List community workflows (newest first)
  info [options] <id>       Display detailed information about a community
                            workflow
  download [options] <id>   Download a community workflow as TypeScript
  help [command]            display help for command
```

### `n8nac skills guides`

```
Usage: n8nac skills guides [options] [query]

Find workflow guides, tutorials, and walkthroughs

Arguments:
  query            Search query

Options:
  --list           List all guides
  --limit <limit>  Limit results (default: "10")
  -h, --help       display help for command
```

### `n8nac skills list`

```
Usage: n8nac skills list [options]

List available nodes, documentation categories, or guides

Options:
  --nodes     List all node names
  --docs      List all documentation categories
  --guides    List all available guides
  --debug     Show custom nodes resolution details on stderr
  -h, --help  display help for command
```

### `n8nac skills mcp`

```
Usage: n8nac skills mcp [options]

Compatibility redirect to `n8nac mcp`

Options:
  --cwd <path>  Project directory used to resolve n8nac-config.json and
                n8nac-custom-nodes.json
  -h, --help    display help for command
```

### `n8nac skills node-info`

```
Usage: n8nac skills node-info [options] <name>

Get complete node information as TypeScript code

Arguments:
  name        Node name (exact, e.g. "googleSheets")

Options:
  --debug     Show custom nodes resolution details on stderr
  --json      Output as JSON instead of TypeScript
  -h, --help  display help for command
```

### `n8nac skills node-schema`

```
Usage: n8nac skills node-schema [options] <name>

Get TypeScript code snippet for a node (quick reference)

Arguments:
  name        Node name

Options:
  --debug     Show custom nodes resolution details on stderr
  --json      Output as JSON instead of TypeScript
  -h, --help  display help for command
```

### `n8nac skills related`

```
Usage: n8nac skills related [options] <query>

Find related nodes and documentation

Arguments:
  query       Node name or concept

Options:
  -h, --help  display help for command
```

### `n8nac skills search`

```
Usage: n8nac skills search [options] <query>

Search for n8n nodes and documentation

Arguments:
  query                  Search query (e.g. "google sheets", "ai agents")

Options:
  --category <category>  Filter by category
  --type <type>          Filter by type (node or documentation)
  --limit <limit>        Limit results (default: "10")
  --debug                Show custom nodes resolution details on stderr
  --json                 Output as JSON instead of TypeScript
  -h, --help             display help for command
```

### `n8nac skills update-ai`

```
Usage: n8nac skills update-ai [options]

Update AI Context files (AGENTS.md)

Options:
  --n8n-version <version>  n8n instance version (default: "Unknown")
  --cli-version <version>  n8nac CLI version or dist-tag to use in generated AI
                           context (default: "latest")
  --cli-cmd <command>      Override the generated n8nac command in AGENTS.md
  --manager-cmd <command>  Override the generated n8n-manager command in
                           AGENTS.md
  -h, --help               display help for command
```

### `n8nac skills validate`

```
Usage: n8nac skills validate [options] <file>

Validate a workflow file (JSON or TypeScript)

Arguments:
  file        Path to workflow file (.json or .workflow.ts)

Options:
  --strict    Treat warnings as errors
  --debug     Show custom nodes resolution details on stderr
  --json      Output the validation result as JSON
  -h, --help  display help for command
```

---

## `n8nac update-ai`

### `n8nac update-ai`

```
Usage: n8nac update-ai [options]

Update AI Context (AGENTS.md and snippets)

Options:
  --n8n-version <version>  n8n instance version to write when API discovery is
                           unavailable
  --cli-version <version>  n8nac CLI dist tag to use in generated AI context
  --cli-cmd <command>      Override the generated n8nac command in AGENTS.md
                           (for local dev builds)
  --manager-cmd <command>  Override the generated n8n-manager command in
                           AGENTS.md (for local dev builds)
  --silent                 Suppress all output (used for background refresh)
  -h, --help               display help for command
```

---

_End of generated reference. 2.3.6_
