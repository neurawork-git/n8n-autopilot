---
name: n8n-code-python
description: Write Python code in n8n Code nodes. Use when writing Python in n8n, using _input/_json/_node syntax, working with standard library, or need to understand Python limitations in n8n Code nodes.
user-invocable: false
---

# Python Code Node (Beta)

Expert guidance for writing Python code in n8n Code nodes.

---

## JavaScript First

**Use JavaScript for 95% of use cases.** Only use Python when:
- You need specific Python standard library functions (e.g. `statistics`)
- You're significantly more comfortable with Python syntax
- You're doing data transformations better suited to Python

JavaScript has `$helpers.httpRequest()`, Luxon DateTime, and better n8n docs.

---

## Quick Start

```python
# Basic template for Python Code nodes
items = _input.all()

processed = []
for item in items:
    processed.append({
        "json": {
            **item["json"],
            "processed": True,
            "timestamp": datetime.now().isoformat()
        }
    })

return processed
```

### Essential Rules

1. **Consider JavaScript first**
2. Access data: `_input.all()`, `_input.first()`, `_input.item`
3. **CRITICAL**: Return `[{"json": {...}}]` format
4. **CRITICAL**: Webhook data is under `_json["body"]`
5. **CRITICAL LIMITATION**: **No external libraries** — no requests, pandas, numpy

---

## CRITICAL: No External Libraries

```python
# ❌ NOT AVAILABLE
import requests   # ModuleNotFoundError
import pandas     # ModuleNotFoundError

# ✅ AVAILABLE (standard library only)
import json
import datetime
import re
import base64
import hashlib
import urllib.parse
import math
import random
import statistics
```

**Workarounds:**
- Need HTTP requests? → Use HTTP Request node before Code node (or switch to JavaScript)
- Need pandas? → Use `statistics` module for basic stats, or switch to JavaScript

---

## Data Access

```python
# All items
all_items = _input.all()

# First item
first_item = _input.first()
data = first_item["json"]

# Each item mode
current_item = _input.item

# Other nodes
webhook_data = _node["Webhook"]["json"]
http_data = _node["HTTP Request"]["json"]
```

---

## CRITICAL: Webhook Data

```python
# ❌ WRONG
name = _json["name"]        # KeyError!

# ✅ CORRECT
name = _json["body"]["name"]

# ✅ SAFER
name = _json.get("body", {}).get("name", "Unknown")
```

---

## Return Format

```python
# ✅ Single result
return [{"json": {"field": value}}]

# ✅ List comprehension
return [{"json": item["json"]} for item in _input.all()]

# ✅ Empty
return []
```

**WRONG:** `return {"json": {...}}` (no list), `return [{"field": value}]` (no json key)

---

## Python Modes

### Python (Beta) — Recommended
Uses `_input`, `_json`, `_node`, `_now` helpers.

```python
items = _input.all()
now = _now  # Built-in datetime

return [{"json": {"count": len(items), "timestamp": now.isoformat()}}]
```

### Python (Native) (Beta)
Uses `_items`, `_item` only — no helpers.

```python
return [{"json": item["json"]} for item in _items]
```

Use **Python (Beta)** for better n8n integration.

---

## Common Patterns

### Filtering + Aggregation

```python
items = _input.all()
total = sum(item["json"].get("amount", 0) for item in items)
valid = [item for item in items if item["json"].get("amount", 0) > 0]

return [{"json": {"total": total, "count": len(valid)}}]
```

### String Processing with Regex

```python
import re

all_emails = []
for item in _input.all():
    emails = re.findall(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b', item["json"].get("text", ""))
    all_emails.extend(emails)

return [{"json": {"emails": list(set(all_emails)), "count": len(set(all_emails))}}]
```

### Statistical Analysis

```python
from statistics import mean, median, stdev

values = [item["json"].get("value", 0) for item in _input.all() if "value" in item["json"]]

if values:
    return [{"json": {"mean": mean(values), "median": median(values), "stdev": stdev(values) if len(values) > 1 else 0}}]
else:
    return [{"json": {"error": "No values found"}}]
```

---

## Top 5 Mistakes

1. **Importing external libraries** → Use HTTP Request node or switch to JavaScript
2. **No return statement** → Always return a list
3. **Wrong return format** → Must be `[{"json": {...}}]`
4. **Direct dict access** → Use `.get()` to avoid KeyError
5. **Webhook body** → `_json["email"]` ❌ → `_json["body"]["email"]` ✅

---

## Best Practices

- Always use `.get()` for dictionary access
- Handle None explicitly: `value = item["json"].get("x") or 0`
- Use list comprehensions for filtering
- Return consistent structure from all code paths
- Debug with `print()` (appears in browser console)

---

## Standard Library Quick Reference

```python
import json          # json.loads(), json.dumps()
from datetime import datetime, timedelta  # datetime.now(), timedelta(days=1)
import re            # re.findall(), re.sub()
import base64        # base64.b64encode(), b64decode()
import hashlib       # hashlib.sha256(text.encode()).hexdigest()
import urllib.parse  # urllib.parse.urlencode(), urlparse()
from statistics import mean, median, stdev
```
