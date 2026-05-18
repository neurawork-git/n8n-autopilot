---
name: n8n-node-configuration
description: Operation-aware node configuration guidance. Use when configuring nodes, understanding property dependencies, determining required fields, choosing between get_node detail levels, or learning common configuration patterns by node type.
user-invocable: false
---

# n8n Node Configuration

## Core Concepts

**Operation-aware:** resource + operation determine which fields are required. Changing operation = different required fields.

**Progressive disclosure:** Start minimal → validate → add as needed.

**Detail level strategy:**
1. `get_node` (standard, default) → 95% of cases, ~1-2K tokens
2. `get_node({mode: "search_properties", propertyQuery: "..."})` → find specific field
3. `get_node({detail: "full"})` → only when standard is insufficient (~3-8K tokens)

## Configuration Process

```
1. get_node({nodeType: "nodes-base.slack"})               → see operations/required fields
2. Configure required fields for chosen operation
3. validate_node({nodeType, config, profile: "runtime"})  → check config
4. Fix errors → validate again (avg 2-3 cycles)
5. Deploy
```

## Key Rules

- **Different operations = different required fields** — always re-check after changing operation
- **Auto-sanitization** handles IF/Switch operator structure — don't manually manage `singleValue`
- **ResourceLocator params** need `{ __rl: true, value: "...", mode: "list" }` (e.g. `model` on `lmChatOpenAi`)
- **Expressions** use `={{ $json.fieldName }}` syntax in parameter strings

## Property Dependencies

See [references/DEPENDENCIES.md](references/DEPENDENCIES.md) for:
- `displayOptions` mechanism (show/hide rules)
- Slack operation matrix, IF operator table
- HTTP Request dependency chain

## Node Patterns

See [references/OPERATION_PATTERNS.md](references/OPERATION_PATTERNS.md) for minimal valid configs:
HTTP Request, Webhook, Slack, Gmail, Postgres, Set, Code, IF, Schedule, AI Agent
