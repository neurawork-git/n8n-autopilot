---
name: data-tables
description: Manage n8n DataTables (CRUD on tables, columns, rows) via the n8n public REST API. Use when the user wants to create/seed/list/delete data-table resources outside of a workflow — n8nac CLI does not support this. Curl is explicitly allowed for `/api/v1/data-tables` (carve-out in PreToolUse hook).
argument-hint: "<operation> [args...] — e.g. list-tables, create-table, seed-rows, drop-table"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(curl:*), Bash(npx:*), Bash(jq:*), Bash(cat:*)
---

# n8n DataTables Admin

n8nac has no commands for DataTable lifecycle (`n8nac datatable` does not exist as of 2.2.x). The only way to create/seed/drop tables outside the n8n UI is the public REST API. This skill encapsulates the exact endpoints + the curl patterns the PreToolUse hook is configured to allow.

> **Carve-out scope:** Only URLs containing `/api/v1/data-tables` are allowed past the REST-block.
> The guard catches `curl`/`wget`/`urllib`/`Invoke-RestMethod`/`requests.` against `/api/v1` — you
> cannot dodge it by switching HTTP tool. Anything else (workflows, credentials, executions) still
> routes through `n8nac` — do not try to reach those via raw HTTP from here.

## Prerequisites

`.env` must define:
```
N8N_API_URL=https://your-instance.example.com
N8N_API_KEY=<key from n8n UI → Settings → API>
```

Source it at the top of every shell invocation:
```bash
set -a; source .env; set +a
BASE="${N8N_API_URL%/}/api/v1/data-tables"
AUTH=(-H "X-N8N-API-KEY: $N8N_API_KEY" -H "Accept: application/json")
```

> **Polling / loops:** to read rows repeatedly, loop the carve-out `curl` — a `curl` against
> `/api/v1/data-tables` inside a `while`/`for` still passes the guard. Do **NOT** switch to
> `python`/`urllib`/`Invoke-RestMethod` to poll (the guard now blocks those too), and do **NOT**
> read n8nac's internal `~/.n8n-manager/secrets.json` for the key — it is undocumented and may
> change. The key is `N8N_API_KEY` (n8n UI → Settings → API, or your secret store / Infisical).

## API Reference (n8n public API v1)

Routes confirmed against `packages/cli/src/public-api/v1/handlers/data-tables/` (master).

### Tables

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/data-tables` | List tables (query: `limit`, `cursor`, `projectId`, `name`) |
| `POST` | `/data-tables` | Create table — body: `{ name, projectId, columns: [{name, type}] }` |
| `GET` | `/data-tables/:id` | Get table with columns |
| `PATCH` | `/data-tables/:id` | Rename / update meta — body: `{ name }` |
| `DELETE` | `/data-tables/:id` | Drop table (cascades rows) |

### Columns

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/data-tables/:id/columns` | List columns |
| `POST` | `/data-tables/:id/columns` | Add column — body: `{ name, type, index? }` (type: `string`, `number`, `boolean`, `date`) |
| `DELETE` | `/data-tables/:id/columns/:colId` | Drop column |
| `PATCH` | `/data-tables/:id/columns/:colId` | Rename / reindex — body: `{ name?, index? }` |

### Rows

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/data-tables/:id/rows` | Query rows — query: `offset`, `limit`, `filter`, `sortBy`, `search` |
| `POST` | `/data-tables/:id/rows` | Append rows — body: `{ data: [{col1: val, col2: val}, ...], returnType? }` |
| `PUT` | `/data-tables/:id/rows` | Upsert — body: `{ filter, data, returnData?, dryRun? }` |
| `PATCH` | `/data-tables/:id/rows` | Update matching — body: `{ filter, data, returnData?, dryRun? }` |
| `DELETE` | `/data-tables/:id/rows` | Delete matching — query: `filter`, `returnData?`, `dryRun?` |

`filter` is n8n's row-filter DSL — typically `{ "type":"and", "filters":[{"columnName":"id","condition":"eq","value":42}] }`. Conditions: `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `like`, `notLike`, `isNull`, `isNotNull`.

## Recipes

### List all tables
```bash
set -a; source .env; set +a
curl -s "${N8N_API_URL%/}/api/v1/data-tables" \
  -H "X-N8N-API-KEY: $N8N_API_KEY" -H "Accept: application/json" | jq .
```

### Create a table with typed columns
```bash
curl -s -X POST "${N8N_API_URL%/}/api/v1/data-tables" \
  -H "X-N8N-API-KEY: $N8N_API_KEY" -H "Content-Type: application/json" \
  --data-binary @- <<'JSON' | jq .
{
  "name": "customer_queue",
  "projectId": "<project-id>",
  "columns": [
    { "name": "customer_id", "type": "string" },
    { "name": "status",      "type": "string" },
    { "name": "retries",     "type": "number" },
    { "name": "last_seen",   "type": "date"   }
  ]
}
JSON
```

> **Umlaut-safe inline JSON on Windows:** Never `curl -d '{"name":"Geschäft"}'` — use a heredoc as shown (`--data-binary @-`) or write the JSON to a temp file and pass `--data-binary @file.json`. See `feedback_curl_umlaut_body.md`.

### Seed rows from a local JSON file
```bash
# rows.json: { "data": [ {"customer_id":"abc","status":"new","retries":0,"last_seen":"2026-05-18T00:00:00Z"}, ... ] }
TABLE_ID=<id>
curl -s -X POST "${N8N_API_URL%/}/api/v1/data-tables/$TABLE_ID/rows" \
  -H "X-N8N-API-KEY: $N8N_API_KEY" -H "Content-Type: application/json" \
  --data-binary @rows.json | jq '.data | length'
```

### Read first 50 rows
```bash
curl -s "${N8N_API_URL%/}/api/v1/data-tables/$TABLE_ID/rows?limit=50" \
  -H "X-N8N-API-KEY: $N8N_API_KEY" | jq '.data'
```

### Upsert rows by key
```bash
curl -s -X PUT "${N8N_API_URL%/}/api/v1/data-tables/$TABLE_ID/rows" \
  -H "X-N8N-API-KEY: $N8N_API_KEY" -H "Content-Type: application/json" \
  --data-binary @- <<'JSON' | jq .
{
  "filter": { "type":"and", "filters":[{"columnName":"customer_id","condition":"eq","value":"abc"}] },
  "data":   { "status":"done", "retries": 1 }
}
JSON
```

### Delete rows by filter
```bash
curl -s -X DELETE "${N8N_API_URL%/}/api/v1/data-tables/$TABLE_ID/rows" \
  -H "X-N8N-API-KEY: $N8N_API_KEY" -G \
  --data-urlencode 'filter={"type":"and","filters":[{"columnName":"status","condition":"eq","value":"obsolete"}]}' \
  | jq .
```

### Drop entire table
```bash
curl -s -X DELETE "${N8N_API_URL%/}/api/v1/data-tables/$TABLE_ID" \
  -H "X-N8N-API-KEY: $N8N_API_KEY" | jq .
```

### Add a column to existing table
```bash
curl -s -X POST "${N8N_API_URL%/}/api/v1/data-tables/$TABLE_ID/columns" \
  -H "X-N8N-API-KEY: $N8N_API_KEY" -H "Content-Type: application/json" \
  -d '{"name":"notes","type":"string"}' | jq .
```

## Workflow Integration

Once a table exists, reference it from a workflow via the **`dataTable` node** (operations: `getRows`, `insertRows`, `updateRows`, `upsertRow`, `deleteRows`). Inside the workflow node, filters use the same DSL — see `feedback_n8n_datatable_upsert.md` for the `filters.conditions[].keyName` quirk.

For node-level discovery:
```bash
npx n8nac skills node-info dataTable --json
```

### Upsert node shape (THREE parts — all required)

A workflow-node upsert needs `filters.conditions` (with `keyName` **+** `condition` **+** `keyValue`)
**AND** `matchingColumns`. Miss any one and the upsert matches nothing and always inserts (→ duplicates).
n8nac validation is authoritative here.

```typescript
{
  operation: 'upsert',
  dataTableId: { __rl: true, value: '<table-id>', mode: 'id' },
  filters: {
    conditions: [{
      keyName:  'matching_column',          // (1) which column to match
      condition: 'eq',                       // (2) MUST be set
      keyValue: '={{ $json.matching_column }}', // (3) MUST be set
    }],
  },
  columns: {
    mappingMode: 'autoMapInputData',
    value: {},
    matchingColumns: ['matching_column'],    // MUST mirror the condition key
    schema: [ /* all columns with correct `type` (match LLM/extractor output types) */ ],
  },
}
```

### Usage patterns (when to reach for a DataTable)

- **Fan-in store for parallel sub-workflows** — each async sub-workflow writes a result row
  (`batch_id`, `item_idx`, `status`, `result`); the parent polls `COUNT(*) WHERE batch_id=X` until it
  reaches N, then reads + merges. The recommended fan-out/fan-in mechanism — see
  `n8n-autopilot:n8n-orchestration-patterns` (Pattern B). Avoids webhook-between-workflows + HMAC pain.
- **Idempotency / dedup** — on retries, **upsert on the natural key** (e.g. `(batch_id, item_idx)`)
  instead of insert, so a re-run overwrites rather than duplicating.
- **Error rows, not silent skips** — route a risky node's **error output** to a DataTable write with
  `status: 'error'` so the fan-in count still completes and the failure is visible. Never
  `continueOnFail: true` (masks silent failures).
- **Cross-run state** — small dedup/seen-tables, processing cursors, last-seen timestamps. For large
  datasets prefer the source DB (DataTables are not a data warehouse).
- **Count-query races** — inserts are atomic per row; append-only `COUNT` is safe without locking.

## Safety

- **Destructive** ops (`DELETE table`, `DELETE rows` without dry-run) — confirm with the user first
- Use `?dryRun=true` query param on PUT/PATCH/DELETE rows when uncertain about the filter scope
- API key has full instance access — never log the key, never commit `.env`
- Operations are **not transactional** across multiple tables — failures partway leave partial state

## Why Not n8nac?

n8nac CLI (`npx n8nac --help`) has no `datatable` / `data-table` subcommand as of 2.2.x. DataTable resources live in the n8n instance, not in the workflow source — they are infrastructure, not code. The public REST API is the canonical management channel until n8nac adds first-class support.
