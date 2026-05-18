---
name: n8n-validation-expert
description: Interpret validation errors and guide fixing them. Use when encountering validation errors, validation warnings, false positives, operator structure issues, or need help understanding validation results. Also use when asking about validation profiles, error types, or the validation loop process.
user-invocable: false
---

# n8n Validation Expert

## Validation Strategy

Two levels, from offline to live. Run them in order — only escalate to Level 2 once Level 1 is clean.

| Level | What | Tool | Catches |
|-------|------|------|---------|
| 1 | n8nac schema validation (offline) | `npx n8nac skills validate <file>` (add `--strict --json` for agent pipelines) | unknown parameter names (silently ignored by n8n at runtime), operation↔resource mismatches, missing required fields, typeVersion mismatches |
| 2 | Live execution (needs n8n) | `npx n8nac push --verify` → `npx n8nac test` | credential issues, real API errors, runtime failures |

## Validation Process

**Iterative by design** — expect 2-3 fix cycles.

```
validate_node → read errors → fix → validate_node again → repeat until valid
```

## Error Severity

- **Errors (must fix):** `missing_required`, `invalid_value`, `type_mismatch`, `invalid_expression`, `invalid_reference`
- **Warnings (review):** `best_practice`, `deprecated`, `performance`
- **Suggestions:** optional improvements

## Validation Profiles

| Profile | Use when |
|---------|----------|
| `minimal` | Quick checks during editing |
| `runtime` | **Pre-deployment (recommended)** |
| `ai-friendly` | AI-generated configs, reduce false positives |
| `strict` | Production deployment |

```javascript
validate_node({ nodeType: "nodes-base.slack", config: {...}, profile: "runtime" })
validate_node({ nodeType: "nodes-base.slack", config: {}, mode: "minimal" })  // required fields only
```

## Auto-Sanitization

Runs automatically on every create/update. **Don't manually fix operator structure.**
- Binary operators → `singleValue` removed
- Unary operators (isEmpty, isNotEmpty, true, false) → `singleValue: true` added
- IF v2.2+ / Switch v3.2+ → `conditions.options` metadata added

Cannot fix: broken connections (`cleanStaleConnections`), branch count mismatches, corrupt states.

## Recovery Strategies

1. **Too many errors:** Build minimal valid config first, add features one by one
2. **"Node not found" errors:** Use `cleanStaleConnections` operation
3. **Operator errors:** Save — auto-sanitization handles it
4. **Bulk fixes:** `n8n_autofix_workflow({ id, applyFixes: true })`

## Workflow Validation Errors

- `Connection to 'X' — target not found` → `cleanStaleConnections` or create missing node
- `Circular dependency` → restructure workflow
- `Multiple triggers` → remove extra or split into workflows
- `Disconnected node` → connect or remove

## Expression Validation

Use `validate_expression` to check n8n expressions before embedding them in workflows:

```javascript
validate_expression({ expression: "={{ $json.body.name }}" })
validate_expression({ expression: "={{ $node['HTTP Request'].json.data }}" })
```

Returns: syntax errors, undefined variable references, type mismatches. Use **before** `validate_node` to catch expression errors early.

## References

- [references/ERROR_CATALOG.md](references/ERROR_CATALOG.md) — all error types with fixes
- [references/FALSE_POSITIVES.md](references/FALSE_POSITIVES.md) — when to accept warnings
