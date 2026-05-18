# Composable Patterns

Reusable workflow patterns for common structures. Implement using `@n8n/workflow-sdk` directly — no pattern library needed.

---

## 1. Validation Gate

**Flow**: `Trigger → IF (fields exist?) → True: continue → False: Error Response (400)`

**When**: Any webhook processing user input.

**SDK**: Use `node({type: "n8n-nodes-base.if"})` with `output(0)` for valid path, `output(1)` for error response.

---

## 2. Agent with Tools

**Flow**: `Input → AI Agent (model + memory + tools) → Output`

**When**: AI-powered processing with external tool access.

**SDK**: Use `languageModel()`, `memory()`, `tool()` wired via `config.subnodes: { model, memory, tools: [...] }`.

---

## 3. RAG Query

**Flow**: `Input → Embeddings → Vector Search → AI Agent → Output`

**When**: Knowledge base queries with semantic search.

**SDK**: Combine `embedding()`, `vectorStore()` as sub-nodes of an AI agent.

---

## 4. Webhook → Transform → Respond

**Flow**: `Webhook → Set Fields (transform) → Respond to Webhook`

**When**: Simple API endpoint that transforms and returns data.

**SDK**: Linear chain `webhookTrigger.to(setNode).to(respondNode)`.

---

## 5. Cron → Fetch → Notify

**Flow**: `Schedule Trigger → HTTP Request → Slack`

**When**: Periodic data fetch with notification.

**SDK**: `trigger({type: "scheduleTrigger"}).to(httpNode).to(slackNode)`.

---

## 6. Retry with Fallback

**Flow**: `Node (retryOnFail: true, maxTries: 3) → on error → Fallback Node`

**When**: External API calls that may fail.

**SDK**: Set `config.retryOnFail: true, config.onError: "continueErrorOutput"`.

---

## 7. Error Notification

**Flow**: `Error Trigger → Set Fields (format) → Slack`

**When**: Standalone error monitoring workflow.

**SDK**: `trigger({type: "n8n-nodes-base.errorTrigger"}).to(formatNode).to(slackNode)`.

---

## 8. Evaluator Loop

**Flow**: `Input → Generator Agent → Evaluator Agent → IF (pass?) → True: Output → False: Merge feedback → Generator (loop)`

**When**: AI content generation mit Qualitätssicherung — E-Mail-Drafts, Support-Antworten, strukturierte Berichte.

**Max. Iterationen:** 3 — danach immer einen Fallback-Output vorsehen.

### Vollständiger Flow

```
Trigger
  → Set Input Variables
    → Generator Agent          ← erhält $json.feedback bei Retry
      → Evaluator Agent
        → IF (pass == true)
            True  → Output / Respond
            False → Set Feedback → (zurück zu Generator Agent via Loop-Node)
```

### Generator Agent — Systempromt-Template

```
Du bist [ROLLE] bei [COMPANY].

Dir wird eine Aufgabe gestellt: {{ $json.task }}

{{ $json.feedback ? 'Vorheriges Feedback des Bewerters:\n' + $json.feedback : '' }}

Erstelle eine Antwort, die folgende Kriterien erfüllt:
- [Kriterium 1]
- [Kriterium 2]
- [Kriterium 3]

Gib nur den finalen Text aus — kein zusätzlicher Kommentar.
```

### Evaluator Agent — Systempromt-Template

```
Du bist der Qualitätsbewerter bei [COMPANY].

Dir wird eine KI-generierte Antwort vorgelegt.

Bewerte die Antwort basierend auf:
- Klarheit und Vollständigkeit
- Ton (professionell, freundlich)
- [Weitere Kriterien]

Gib deine Bewertung als gültiges JSON zurück:
- Bestanden: {"pass": true}
- Nicht bestanden: {"pass": false, "feedback": "Konkrete Verbesserungsvorschläge"}

Keine zusätzlichen Schlüssel oder Text außerhalb der JSON-Struktur.
```

### Output Parser Schema (Structured Output Parser Node)

```typescript
@node({
  name: 'Parse Evaluation',
  type: '@n8n/n8n-nodes-langchain.outputParserStructured',
  version: 1.3,
})
ParseEvaluation = {
  parameters: {
    schemaType: 'manual',
    inputSchema: JSON.stringify({
      type: 'object',
      properties: {
        pass: { type: 'boolean' },
        feedback: { type: 'string' }
      },
      required: ['pass']
    })
  }
};
```

### IF-Node für pass-Check

```typescript
@node({
  name: 'Check Quality',
  type: 'n8n-nodes-base.if',
  version: 2.2,
})
CheckQuality = {
  parameters: {
    conditions: {
      options: { caseSensitive: true, typeValidation: 'strict' },
      conditions: [{
        leftValue: '={{ $json.pass }}',
        rightValue: true,
        operator: { type: 'boolean', operation: 'equals' }
      }]
    }
  }
};
```

### Verbindungen

```typescript
@links()
defineRouting() {
  this.Trigger.out(0).to(this.SetInput.in(0));
  this.SetInput.out(0).to(this.GeneratorAgent.in(0));
  this.GeneratorAgent.out(0).to(this.EvaluatorAgent.in(0));
  this.EvaluatorAgent.out(0).to(this.CheckQuality.in(0));
  this.CheckQuality.out(0).to(this.Output.in(0));       // True: pass
  this.CheckQuality.out(1).to(this.SetFeedback.in(0));  // False: retry
  this.SetFeedback.out(0).to(this.GeneratorAgent.in(0)); // Loop zurück

  // AI sub-nodes
  this.GeneratorAgent.uses({ ai_languageModel: this.GeneratorModel, ai_outputParser: this.ParseEvaluation });
  this.EvaluatorAgent.uses({ ai_languageModel: this.EvaluatorModel });
}
```

---

## Reference Implementations

See `workflows/` for working SDK examples of these patterns:
- **Validation Gate**: `webhook_lead` (IF + true/false branches)
- **Agent with Tools**: `ai_agent_support` (model + memory + tool sub-nodes)
- **Webhook → Transform → Respond**: `apify_scrape_pipeline`, `qdrant_community_vectors`
- **Cron → Fetch → Notify**: `scheduled_sync`
- **AI + Scraping**: `firecrawl_ai_scraper` (scrape → AI summarize)
