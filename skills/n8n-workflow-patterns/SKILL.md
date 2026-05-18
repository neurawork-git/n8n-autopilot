---
name: n8n-workflow-patterns
description: Proven workflow architectural patterns from real n8n workflows. Use when building new workflows, designing workflow structure, choosing workflow patterns, planning workflow architecture, or asking about webhook processing, HTTP API integration, database operations, AI agent workflows, or scheduled tasks.
user-invocable: false
---

# n8n Workflow Patterns

Proven architectural patterns for building n8n workflows.

---

## The 5 Core Patterns

Based on analysis of real workflow usage:

1. **[Webhook Processing](references/webhook_processing.md)** (Most Common)
   - Receive HTTP requests → Process → Output
   - Pattern: Webhook → Validate → Transform → Respond/Notify

2. **[HTTP API Integration](references/http_api_integration.md)**
   - Fetch from REST APIs → Transform → Store/Use
   - Pattern: Trigger → HTTP Request → Transform → Action → Error Handler

3. **[Database Operations](references/database_operations.md)**
   - Read/Write/Sync database data
   - Pattern: Schedule → Query → Transform → Write → Verify

4. **[AI Agent Workflow](references/ai_agent_workflow.md)**
   - AI agents with tools and memory
   - Pattern: Trigger → AI Agent (Model + Tools + Memory) → Output

5. **[Scheduled Tasks](references/scheduled_tasks.md)**
   - Recurring automation workflows
   - Pattern: Schedule → Fetch → Process → Deliver → Log

---

## Pattern Selection Guide

### When to use each pattern:

**Webhook Processing** - Use when:
- Receiving data from external systems
- Building integrations (Slack commands, form submissions, GitHub webhooks)
- Need instant response to events
- Example: "Receive Stripe payment webhook → Update database → Send confirmation"

**HTTP API Integration** - Use when:
- Fetching data from external APIs
- Synchronizing with third-party services
- Building data pipelines
- Example: "Fetch GitHub issues → Transform → Create Jira tickets"

**Database Operations** - Use when:
- Syncing between databases
- Running database queries on schedule
- ETL workflows
- Example: "Read Postgres records → Transform → Write to MySQL"

**AI Agent Workflow** - Use when:
- Building conversational AI
- Need AI with tool access
- Multi-step reasoning tasks
- Example: "Chat with AI that can search docs, query database, send emails"

**Scheduled Tasks** - Use when:
- Recurring reports or summaries
- Periodic data fetching
- Maintenance tasks
- Example: "Daily: Fetch analytics → Generate report → Email team"

---

## Workflow Checklist

**Plan:** pattern → required nodes → data flow → error handling strategy

**Build:** trigger → data sources → transform (Set/Code/IF) → output → error handling

**Validate:** `validate_node` each node → `validate_workflow` → test with sample data

**Deploy:** `activateWorkflow` → monitor first executions

---

## Sub-Workflow-Entscheidung (3R-Regel)

Erstelle einen Sub-Workflow, wenn **2 von 3** Kriterien zutreffen:

| Kriterium | Frage |
|-----------|-------|
| **Reusable** | Wird diese Logik von 2+ Workflows genutzt? |
| **Replaceable** | Kann dieser Teil unabhängig aktualisiert werden? |
| **Responsible** | Hat dieser Teil genau eine klar abgegrenzte Aufgabe? |

**Node-Limit:** Ab 30–40 Nodes einen Sub-Workflow erwägen — n8n wird bei sehr großen Workflows langsamer und schwerer zu debuggen.

**Einstiegspunkt** im Sub-Workflow: `n8n-nodes-base.executeWorkflowTrigger`

```typescript
@node({
  name: 'Start',
  type: 'n8n-nodes-base.executeWorkflowTrigger',
  version: 1,
})
Start = {};
```

**Aufruf** aus dem Haupt-Workflow via `n8n-nodes-base.executeWorkflow` mit der Workflow-ID.

---

## Data Flow Patterns

### Linear Flow
```
Trigger → Transform → Action → End
```
**Use when**: Simple workflows with single path

### Branching Flow
```
Trigger → IF → [True Path]
             └→ [False Path]
```
**Use when**: Different actions based on conditions

### Parallel Processing
```
Trigger → [Branch 1] → Merge
       └→ [Branch 2] ↗
```
**Use when**: Independent operations that can run simultaneously

### Loop Pattern
```
Trigger → Split in Batches → Process → Loop (until done)
```
**Use when**: Processing large datasets in chunks

### Error Handler Pattern
```
Main Flow → [Success Path]
         └→ [Error Trigger → Error Handler]
```
**Use when**: Need separate error handling workflow

---

## Common Gotchas

- Webhook payload: `$json.body.field` not `$json.field`
- Expressions must use `={{ }}` syntax
- Node execution order: Settings → v1 (connection-based, recommended)
- Auth failures: use Credentials section, not parameters

---

## Detailed Pattern Files

For comprehensive guidance on each pattern:

- **[webhook_processing.md](references/webhook_processing.md)** - Webhook patterns, data structure, response handling
- **[http_api_integration.md](references/http_api_integration.md)** - REST APIs, authentication, pagination, retries
- **[database_operations.md](references/database_operations.md)** - Queries, sync, transactions, batch processing
- **[ai_agent_workflow.md](references/ai_agent_workflow.md)** - AI agents, tools, memory, langchain nodes
- **[scheduled_tasks.md](references/scheduled_tasks.md)** - Cron schedules, reports, maintenance tasks
- **[composable_patterns.md](references/composable_patterns.md)** - Validation Gate, RAG Pipeline, Evaluator Loop, Error Notification

Use `npx n8nac skills examples search` for real examples. Template #2947: Weather to Slack (Schedule → HTTP → Set → Slack).
