# Operation Patterns — Quick Reference

Common minimal configs for top nodes. Always validate before deploying.

## HTTP Request

```javascript
// GET
{ method: "GET", url: "https://api.example.com/users", authentication: "none" }

// POST JSON
{ method: "POST", url: "...", authentication: "none", sendBody: true,
  body: { contentType: "json", content: { name: "={{$json.name}}", email: "={{$json.email}}" } } }

// With auth
{ method: "GET", url: "...", authentication: "predefinedCredentialType", nodeCredentialType: "httpHeaderAuth" }
```
**Gotcha:** POST/PUT/PATCH require `sendBody: true`. Webhook data is under `$json.body`.

## Webhook

```javascript
{ path: "my-webhook", httpMethod: "POST", responseMode: "onReceived" }
```
**Gotcha:** Payload at `$json.body.fieldName`, not `$json.fieldName`.

## Slack

```javascript
// Post message
{ resource: "message", operation: "post", channel: "#general", text: "Hello!" }

// Update message
{ resource: "message", operation: "update", messageId: "1234567890.123456", text: "Updated!" }

// Create channel
{ resource: "channel", operation: "create", name: "new-channel", isPrivate: false }
```
**Gotcha:** Channel must be `#name` (lowercase). `update` needs `messageId`, not `channel`.

## Gmail

```javascript
{ resource: "message", operation: "send", to: "={{$json.email}}", subject: "...", message: "..." }
{ resource: "message", operation: "getAll", returnAll: false, limit: 50, filters: { q: "is:unread" } }
```

## Postgres

```javascript
// Always use parameterized queries!
{ operation: "executeQuery", query: "SELECT * FROM users WHERE email = $1",
  additionalFields: { mode: "list", queryParameters: "={{$json.email}}" } }

{ operation: "insert", table: "users", columns: "name,email",
  additionalFields: { mode: "list", queryParameters: "={{$json.name}},={{$json.email}}" } }
```
**Gotcha:** Never interpolate user input into SQL strings — use `$1, $2` parameters.

## Set

```javascript
{ mode: "manual", duplicateItem: false,
  assignments: { assignments: [
    { name: "fullName", value: "={{$json.firstName}} {{$json.lastName}}", type: "string" },
    { name: "count", value: 100, type: "number" }
  ] } }
```
**Gotcha:** Use correct `type` per field (string/number/boolean).

## Code

```javascript
{ mode: "runOnceForEachItem", jsCode: "const d = $input.item.json;\nreturn { json: { name: d.name.toUpperCase() } };" }
```
**Gotcha:** Use `$input.item.json` — NOT `={{ }}` expressions in jsCode.

## IF

```javascript
// Binary (equals)
{ conditions: { string: [{ value1: "={{$json.status}}", operation: "equals", value2: "active" }] } }

// Unary (isEmpty) — no value2, singleValue auto-added
{ conditions: { string: [{ value1: "={{$json.email}}", operation: "isEmpty" }] } }

// Multiple conditions AND
{ conditions: { string: [...], number: [...] }, combineOperation: "all" }
```

## Schedule Trigger

```javascript
{ rule: { interval: [{ field: "minutes", minutesInterval: 15 }] } }
// Always set timezone!
{ mode: "cron", cronExpression: "0 9 * * *", timezone: "Europe/Berlin" }
```

## AI Agent Pattern

```javascript
// Nodes wired via .uses() in @links(), NOT via .out().to()
Agent.uses({ ai_languageModel: OpenAiModel, ai_memory: Memory, ai_tool: [SearchTool] })
```
