# Error Catalog

## Error Types (must fix)

| Type | Priority | Auto-fix |
|------|----------|----------|
| `missing_required` | Highest | ❌ |
| `invalid_value` | High | ❌ |
| `type_mismatch` | Medium | ❌ |
| `invalid_expression` | Medium | ❌ |
| `invalid_reference` | Low | ❌ |
| `operator_structure` | Warning | ✅ |

## missing_required (45% of errors)

Add the field. Use `get_node` to see what's required per operation.

Common cases:
- Slack `post` → missing `channel`
- HTTP Request → missing `url`
- Postgres `executeQuery` → missing `query`
- HTTP Request POST → `sendBody: true` but missing `body`

## invalid_value (28%)

Value doesn't match allowed enum. Enums are case-sensitive.

```javascript
// Wrong                    // Fix
operation: "send"       →   operation: "post"
method: "FETCH"         →   method: "GET"
channel: "General"      →   channel: "#general"
resource: "Message"     →   resource: "message"
```

## type_mismatch (12%)

```javascript
limit: "100"            →   limit: 100          // string → number
channel: 12345          →   channel: "#general" // number → string
sendHeaders: "true"     →   sendHeaders: true   // string → boolean
tags: {tag: "x"}        →   tags: ["x"]         // object → array
```

## invalid_expression (8%)

```javascript
text: "$json.name"                           →  text: "={{$json.name}}"
text: "={{$json.body.email}}"                // webhook data under .body!
value: "={{$node['HTTP Requets'].json.data}" →  // fix typo in node name
text: "={{$json.data?.user?.name || '?'}}"   // safe navigation for nested
```

## invalid_reference (5%)

Node renamed/deleted. Use `cleanStaleConnections`:
```javascript
n8n_update_partial_workflow({ id, operations: [{ type: "cleanStaleConnections" }] })
```

## operator_structure (auto-fixed)

Do nothing. Auto-sanitization handles this on save.
- Binary operators → `singleValue` removed
- Unary operators (isEmpty, isNotEmpty) → `singleValue: true` added
