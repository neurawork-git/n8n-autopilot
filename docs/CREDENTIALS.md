# Credential Reference

How to configure credentials for n8nac Decorator-TS workflows.

---

## Quick Start

1. Open n8n UI → **Credentials** → Click a credential → Copy **ID from URL**
2. Use directly in `.workflow.ts`:

```typescript
@node({
  type: "n8n-nodes-base.slack",
  // ...
})
slackMessage() {
  return {
    parameters: {
      authentication: "oAuth2",
      resource: "message",
      operation: "post",
      channel: "#ops",
      text: "Done",
    },
    credentials: {
      slackOAuth2Api: { id: "fgEYaDirOTV5nGhJ", name: "Slack account" },
    },
  };
}
```

---

## Authentication Parameter (CRITICAL)

Some nodes support multiple credential types (e.g., access token vs OAuth2), controlled by an `authentication` parameter. If the credential key doesn't match the default, set `authentication` explicitly.

Always check `get_n8n_node_info` for `authentication` or `displayOptions.show` on credential entries.

---

## Credential IDs (Instance-Specific)

Credential IDs are tied to your n8n instance. To populate them:

```bash
/n8n-autopilot:sync-credentials
```

This pulls live credential IDs from your active instance and reports them as a ready-to-paste table. Example shape:

| Key | n8n Type | ID | Name |
|-----|----------|-----|------|
| openai | `openAiApi` | `<your-id>` | OpenAI account |
| slack | `slackOAuth2Api` | `<your-id>` | Slack account |
| postgres | `postgres` | `<your-id>` | Postgres |

The plugin does not ship hardcoded IDs — every clone of this repo discovers its own.

---

## Supported Credential Types

| n8n Type | Service | Node Types Using It |
|----------|---------|-------------------|
| `openAiApi` | OpenAI API | OpenAI Chat Model, OpenAI Embeddings, GPT nodes |
| `anthropicApi` | Anthropic API | Anthropic Chat Model |
| `postgres` | PostgreSQL | Postgres, Postgres Chat Memory |
| `slackOAuth2Api` | Slack | Slack |
| `googleSheetsOAuth2Api` | Google Sheets | Google Sheets |
| `googleDriveOAuth2Api` | Google Drive | Google Drive |
| `gmailOAuth2` | Gmail | Gmail |
| `googleCalendarOAuth2Api` | Google Calendar | Google Calendar |
| `googleContactsOAuth2Api` | Google Contacts | Google Contacts |
| `qdrantApi` | Qdrant Vector DB | Qdrant Vector Store |
| `telegramApi` | Telegram | Telegram, Telegram Trigger |
| `firecrawlApi` | Firecrawl | Firecrawl |
| `closeApi` | Close CRM | Close CRM |
| `apifyApi` | Apify | Apify |
| `notionApi` | Notion | Notion |
| `firefliesApi` | Fireflies.ai | Fireflies |
| `azureOpenAiApi` | Azure OpenAI | Azure OpenAI Chat Model |

---

## Adding / Syncing Credentials

The authoritative source is always the live n8n instance. To sync:

```bash
npx n8nac credential list
```

Then update the table above with the output.

To add a new credential: create it in the n8n UI, run the sync command above, add the new row to the table.

