# Property Dependencies

Fields show/hide based on other field values via `displayOptions`. Conditions use AND logic (multiple keys), values use OR logic (array).

```javascript
// body shows when: sendBody=true AND method IN (POST, PUT, PATCH)
{ "name": "body", "displayOptions": { "show": { "sendBody": [true], "method": ["POST","PUT","PATCH"] } } }
```

## Key Patterns

**Boolean toggle:** `sendBody: true` → body appears
**Operation cascade:** resource+operation → different required fields
**Method-specific:** GET has no body, POST/PUT/PATCH do

## Slack Operation Matrix

| Field | post | update | delete | get |
|-------|------|--------|--------|-----|
| channel | Required | Optional | Required | Required |
| text | Required | Required | Hidden | Hidden |
| messageId | Hidden | Required | Required | Required |

## IF Operator Table

| Operator | value1 | value2 | singleValue |
|----------|--------|--------|-------------|
| equals, contains, greaterThan… | Required | Required | false |
| isEmpty, isNotEmpty, true, false | Required | Hidden | true (auto-added) |

## HTTP Request Dependency Chain

```
method=POST → sendBody visible → sendBody=true → body required → body.contentType=json → body.content required
```

## Troubleshooting

- **"Field required but not visible"** → `get_node({mode: "search_properties", propertyQuery: "fieldname"})`
- **"Field disappears after operation change"** → re-check requirements with `get_node`
- **"Field doesn't save"** → field hidden by dependencies (e.g. body with method=GET)
