# False Positives — When to Accept Warnings

~40% of warnings are acceptable in specific use cases. Use `ai-friendly` profile to reduce by 60%.

## Decision: Fix or Accept?

```
Security warning?       → Always fix
Production + critical?  → Fix
Dev/test/non-critical?  → Often acceptable
Known n8n issue?        → Accept (see below)
```

**Golden rule:** If you accept a warning, you understand why.

## Common Acceptable Warnings

| Warning | When acceptable |
|---------|----------------|
| No error handling | Dev/test, non-critical notifications, manual-trigger workflows |
| No retry logic | Internal APIs, idempotent GETs, APIs with built-in retry (Stripe) |
| Missing rate limiting | Internal APIs, low-volume workflows (e.g. once/day) |
| Unbounded query | Small known datasets, aggregation queries (COUNT/SUM) |
| Missing input validation | Internal/trusted webhooks (Stripe signed) |

## Always Fix

- Security/hardcoded credentials
- SQL injection risks
- Production automation errors

## Known n8n False Positives (always acceptable)

- **Issue #304** — IF node missing metadata: auto-fixed on save, ignore
- **Issue #306** — Switch extra output with fallback: intentional, ignore
- **Issue #338** — Credentials invalid in static validation: validated at runtime, ignore

## Profile Strategy

- **Development:** `ai-friendly` (fewer warnings)
- **Pre-production:** `runtime` (balanced)
- **Production:** `strict` (review all warnings)
