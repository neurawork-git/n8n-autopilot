---
name: n8n-code-javascript
description: Write JavaScript code in n8n Code nodes. Use when writing JavaScript in n8n, using $input/$json/$node syntax, making HTTP requests with $helpers, working with dates using DateTime, troubleshooting Code node errors, or choosing between Code node modes.
user-invocable: false
---

# JavaScript Code Node

Expert guidance for writing JavaScript code in n8n Code nodes.

---

## Quick Start

```javascript
// Basic template for Code nodes
const items = $input.all();

// Process data
const processed = items.map(item => ({
  json: {
    ...item.json,
    processed: true,
    timestamp: new Date().toISOString()
  }
}));

return processed;
```

### Essential Rules

1. **Choose "Run Once for All Items" mode** (recommended for most use cases)
2. **Access data**: `$input.all()`, `$input.first()`, or `$input.item`
3. **CRITICAL**: Must return `[{json: {...}}]` format
4. **CRITICAL**: Webhook data is under `$json.body` (not `$json` directly)
5. **Built-ins available**: $helpers.httpRequest(), DateTime (Luxon), $jmespath()

---

## Mode Selection Guide

### Run Once for All Items (Recommended - Default)

**Use for:** 95% of use cases — aggregation, filtering, batch processing, transformations

```javascript
const allItems = $input.all();
const total = allItems.reduce((sum, item) => sum + (item.json.amount || 0), 0);

return [{
  json: { total, count: allItems.length, average: total / allItems.length }
}];
```

### Run Once for Each Item

**Use for:** Specialized cases — per-item validation, independent operations

```javascript
const item = $input.item;

return [{
  json: { ...item.json, processed: true, processedAt: new Date().toISOString() }
}];
```

**Decision:** Need to compare multiple items? → All Items. Each item independent? → Each Item. Not sure? → All Items.

---

## Data Access Patterns

```javascript
// Most common: all items
const allItems = $input.all();

// Single result
const firstItem = $input.first();
const data = firstItem.json;

// Reference other nodes
const webhookData = $node["Webhook"].json;
const httpData = $node["HTTP Request"].json;
```

---

## CRITICAL: Webhook Data Structure

Webhook data is nested under `.body`:

```javascript
// ❌ WRONG
const name = $json.name;

// ✅ CORRECT
const name = $json.body.name;
const webhookData = $input.first().json.body;
```

---

## Return Format Requirements

```javascript
// ✅ Single result
return [{ json: { field1: value1 } }];

// ✅ Multiple results
return items.map(item => ({ json: { id: item.json.id, processed: true } }));

// ✅ Empty result
return [];
```

**WRONG:** `return {json: {...}}` (no array), `return [{field: value}]` (no json key)

---

## Built-in Functions

### $helpers.httpRequest()

```javascript
const response = await $helpers.httpRequest({
  method: 'GET',
  url: 'https://api.example.com/data',
  headers: { 'Authorization': 'Bearer token' }
});

return [{ json: { data: response } }];
```

### DateTime (Luxon)

```javascript
const now = DateTime.now();
const formatted = now.toFormat('yyyy-MM-dd');
const tomorrow = now.plus({ days: 1 });
```

### $jmespath()

```javascript
const adults = $jmespath(data, 'users[?age >= `18`]');
const names = $jmespath(data, 'users[*].name');
```

---

## Common Patterns

### Aggregation

```javascript
const items = $input.all();
const total = items.reduce((sum, item) => sum + (item.json.amount || 0), 0);

return [{ json: { total, count: items.length, average: total / items.length } }];
```

### Filtering + Transformation

```javascript
return $input.all()
  .filter(item => item.json.status === 'active')
  .map(item => ({ json: { id: item.json.id, name: item.json.name } }));
```

### Error Handling

```javascript
try {
  const response = await $helpers.httpRequest({ url: 'https://api.example.com/data' });
  return [{ json: { success: true, data: response } }];
} catch (error) {
  return [{ json: { success: false, error: error.message } }];
}
```

---

## Top 5 Mistakes

1. **No return statement** → Add `return items.map(item => ({json: item.json}));`
2. **Using `{{ }}` in Code node** → Use `$json.field` directly (no braces)
3. **Wrong return wrapper** → Must be `[{json: {...}}]`, not `{json: {...}}`
4. **Missing null checks** → Use `item.json?.user?.email || 'fallback'`
5. **Webhook body** → `$json.email` ❌ → `$json.body.email` ✅

---

## Best Practices

- Always validate input: `if (!items || items.length === 0) return [];`
- Use try-catch for async operations
- Prefer `map`/`filter` over manual loops
- Filter early, process late
- Debug with `console.log()`

---

## When to Use Code Node

✅ Complex transformations, custom calculations, API response parsing, multi-step conditionals, data aggregation

❌ Simple field mapping → Set node | Basic filtering → Filter node | HTTP requests → HTTP Request node
