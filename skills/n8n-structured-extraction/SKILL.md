---
name: n8n-structured-extraction
description: Extract or classify structured data from text/documents with an LLM in n8n using a real JSON schema. Use when a workflow needs structured fields out of unstructured input (invoice/contract/email extraction, classification), when deciding between an AI Agent and a dedicated extractor node, or when LLM JSON output is unreliable / fails schema validation.
user-invocable: false
---

# n8n Structured Extraction (JSON-schema-driven)

For ANY structured output (extraction, classification) use a **dedicated structured node with a real
JSON schema** — never an AI-Agent node with a "return JSON" prompt, never tolerant re-parsing of raw
text. This is state-of-the-art LLM document extraction, proven in production (supplier-check and
invoice-extraction pipelines).

## Use the right node

| Task | Node | Output |
|---|---|---|
| Pull fields out of a document/text | `@n8n/n8n-nodes-langchain.informationExtractor` | one object matching your schema |
| Route input into categories | `@n8n/n8n-nodes-langchain.textClassifier` | one output branch per category |

## Why NOT an AI-Agent + "give me JSON"

Agent (Tools Agent) + `outputParserStructured` + reasoning models (gpt-5.x) **fail reproducibly**:
- the model wraps the result in `{"output": {...}}` → top-level schema mismatch,
- and violates enums (`"verlängert"` instead of the schema's `"verlaengert"`).

Prompt-only JSON is fragile. The Information-Extractor / Text-Classifier nodes use the model's
**native structured-output / function-calling** and enforce the schema cleanly.

## How to apply

**Every schema field gets a `type` AND a `description`.** The description is an instruction to the
model (format hints), not decoration. Types must match the downstream sink (e.g. DataTable column
types: number↔number, string↔string). Use real umlauts (ä, ö, ü, ß) in descriptions — never ASCII
transcriptions.

```jsonc
// Information Extractor — manual JSON schema (nested arrays OK)
{
  "type": "object",
  "properties": {
    "rechnungsnummer": { "type": "string",  "description": "Rechnungs-/Belegnummer wie auf dem Dokument" },
    "rechnungsdatum":  { "type": "string",  "description": "Rechnungsdatum als ISO-Datum, z.B. 2026-05-29" },
    "nettobetrag":     { "type": "number",  "description": "Nettobetrag in EUR, nur Zahl ohne Währungssymbol" },
    "steuersatz":      { "type": "number",  "description": "Umsatzsteuersatz in Prozent, z.B. 19" },
    "ev_typ":          { "type": "string",  "enum": ["einfach", "erweitert", "verlaengert"],
                         "description": "Art des Eigentumsvorbehalts. ASCII-Enum-Werte exakt verwenden." },
    "positionen": {
      "type": "array",
      "description": "Einzelpositionen der Rechnung",
      "items": {
        "type": "object",
        "properties": {
          "bezeichnung": { "type": "string", "description": "Artikel-/Leistungsbezeichnung" },
          "betrag":      { "type": "number", "description": "Positionsbetrag netto in EUR" }
        }
      }
    }
  }
}
```

**Rules of thumb**
- Type conversion belongs in the schema, NOT in a downstream Code node — no manual `toNum()`/`toString()`.
- Describe every field with a concrete format hint ("als Jahreszahl, z.B. 2038", "in EUR/m²").
- Enums: define ASCII-safe values and say so in the description — reasoning models otherwise emit the
  pretty/umlaut form and fail validation.
- For classification, prefer the Text Classifier (one branch per category) over an extractor with a
  category field — the branches make downstream routing explicit.
- Reasoning models (gpt-5.x): `max_completion_tokens` + `temperature: 1` where the model requires it.

## Anti-patterns
- ❌ AI-Agent node prompted to "return JSON" + parse the text afterwards.
- ❌ `outputParserStructured` hung off an Agent for reasoning models — top-level `{"output":...}` wrap.
- ❌ Fixing bad LLM JSON in a Code node (toNum/regex) instead of tightening the schema + descriptions.
- ❌ Untyped/undescribed schema fields — the model guesses the format.
