---
name: n8n-expression-syntax
description: Validate n8n expression syntax and fix common errors. Use when writing n8n expressions, using {{}} syntax, accessing $json/$node variables, troubleshooting expression errors, or working with webhook data in workflows.
user-invocable: false
---

# n8n Expression Syntax

Expert guide for writing correct n8n expressions in workflows.

---

## Expression Format

All dynamic content in n8n uses **double curly braces**:

```
={{expression}}
```

In string fields use `={{...}}` for the full value, or inline `text {{...}} more text` for mixed content.

---

## Core Variables

```javascript
// Current node output
={{$json.fieldName}}
={{$json['field with spaces']}}
={{$json.nested.property}}
={{$json.items[0].name}}

// Other nodes
={{$node["Node Name"].json.fieldName}}
={{$node["HTTP Request"].json.data}}

// Current timestamp
={{$now.toFormat('yyyy-MM-dd')}}
={{$now.plus({days: 7})}}

// Environment variables
={{$env.API_KEY}}
```

---

## CRITICAL: Webhook Data Structure

Webhook data is **NOT** at the root — it's under `.body`:

```javascript
// Webhook node output:
{
  "headers": {...},
  "params": {...},
  "query": {...},
  "body": {           // USER DATA IS HERE
    "name": "John",
    "email": "john@example.com"
  }
}

// ❌ WRONG
={{$json.name}}
={{$json.email}}

// ✅ CORRECT
={{$json.body.name}}
={{$json.body.email}}
```

---

## Common Patterns

```javascript
// Nested fields
={{$json.user.email}}
={{$json.data[0].name}}
={{$json['field name']}}

// Reference other nodes
={{$node["HTTP Request"].json.data}}
={{$node["Webhook"].json.body.email}}

// Combine variables (mixed content)
Hello ={{$json.body.name}}!
https://api.example.com/users/={{$json.body.user_id}}

// Ternary
={{$json.status === 'active' ? 'Active' : 'Inactive'}}

// Default value
={{$json.email || 'no-email@example.com'}}

// Date formatting
={{$now.toFormat('yyyy-MM-dd')}}
={{$now.minus({hours: 24}).toISO()}}

// String methods
={{$json.email.toLowerCase()}}
={{$json.tags.split(',').join(', ')}}

// Math
={{$json.price * 1.1}}
```

---

## When NOT to Use Expressions

```javascript
// ❌ Code nodes — use JavaScript directly
const email = '={{$json.email}}';  // WRONG
const email = $json.email;         // CORRECT

// ❌ Webhook paths (static only)
path: "={{$json.user_id}}/webhook"  // WRONG
path: "user-webhook"                // CORRECT

// ❌ Credential fields — use n8n credential system
apiKey: "={{$env.API_KEY}}"         // WRONG
```

---

## Validation Rules

1. **Always use `={{ }}`** — bare `$json.field` is treated as literal text
2. **Quote names with spaces** → `$json['field name']`, `$node["HTTP Request"]`
3. **Node names are case-sensitive** → must match exactly
4. **No nested braces** → `{{{$json.field}}}` ❌, `={{$json.field}}` ✅

---

## Quick Fix Table

| Mistake | Fix |
|---------|-----|
| `$json.field` | `={{$json.field}}` |
| `={{$json.field name}}` | `={{$json['field name']}}` |
| `={{$node.HTTP Request}}` | `={{$node["HTTP Request"]}}` |
| `={{$json.name}}` (webhook) | `={{$json.body.name}}` |
| `='={{$json.email}}'` in Code | `$json.email` |

---

## Data Types in Expressions

```javascript
// Arrays
={{$json.users[0].email}}
={{$json.users.length}}

// Objects
={{$json.user.email}}
={{$json['user data'].email}}

// Strings
={{$json.email.toLowerCase()}}
={{$json.name.toUpperCase()}}

// Numbers
={{$json.price * 1.1}}
={{$json.quantity + 5}}
```

---

## Summary

**5 Essential Rules:**
1. Wrap in `={{ }}`
2. Webhook data is under `.body`
3. No `={{ }}` in Code nodes
4. Quote node names with spaces
5. Node names are case-sensitive
