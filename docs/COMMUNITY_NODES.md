# Community Nodes Registry

**15 verified Community Nodes** available for use in workflows.
Community nodes are searchable via `npx n8nac skills search` (547 indexed).
This document contains additional configuration notes and credential type references.
⚠️ Qdrant and MCP Client are CORE nodes, available by default in n8n.

## Quick Reference

| Package | Nodes | Category | Use Case | Schema |
|---------|-------|----------|----------|--------|
| [@apify/n8n-nodes-apify](#apify) | Apify, Apify Trigger | Scraping | Web scraping at scale | ✅ cached |
| [@firefliesai/n8n-nodes-fireflies](#fireflies) | Fireflies | Meetings | Meeting transcription | ✅ cached |
| [@mendable/n8n-nodes-firecrawl](#firecrawl) | Firecrawl | Scraping | Website → markdown | ✅ cached |
| [n8n-nodes-awork](#awork) | awork | Project Mgmt | Task/time tracking | ✅ cached |
| [n8n-nodes-close-crm](#close-crm) | Close CRM (3 nodes) | CRM | Sales automation | ✅ cached |
| [n8n-nodes-docx-extractor](#docx-extractor) | Docx Extractor | Documents | Extract text from .docx | ✅ cached |
| [n8n-nodes-docxtemplater-pdf-converter](#docxtemplater) | DocXTempler | Documents | Generate docs/PDFs | ✅ cached |
| [n8n-nodes-easybill](#easybill) | EasyBill | Finance | German invoicing | ✅ cached |
| [n8n-nodes-mcp](#mcp-community) | MCP Client | AI/LLM | MCP server integration | ✅ cached |
| [n8n-nodes-pandadoc](#pandadoc) | PandaDoc (2 nodes) | Documents | E-signature workflow | ✅ cached |
| [n8n-nodes-qdrant](#qdrant-community) | Qdrant | Vector DB | Semantic search/RAG | ✅ cached |
| [n8n-nodes-run-node-with-credentials-x](#credentials-x) | Credentials X | Utility | Dynamic credentials | ✅ cached |
| [n8n-nodes-soap](#soap) | SOAP Request | API | Legacy SOAP APIs | ✅ cached |
| [@mbakgun/n8n-nodes-slack-socket-mode](#slack-socket) | Slack Socket Mode | Communication | Real-time Slack events | ✅ cached |
| [n8n-nodes-notion-advanced](#notion-advanced) | Notion Advanced | Productivity | Enhanced Notion API | ✅ cached |

## Detailed Nodes

### <a name="apify"></a>Apify
**Package:** `@apify/n8n-nodes-apify` v0.6.5 | **Type:** `@apify/n8n-nodes-apify.apify` (+ trigger)
Web scraping platform - run actors (pre-built scrapers) | **Credential:** `apifyApi`

**Actors:** `Run Actor`, `Scrape Single URL`, `Get Last Run`
**Tasks:** `Run Task`
**Runs:** `Get User Runs List`, `Get Run`, `Get Runs`
**Storage:** `Get Items`, `Get Record`
**Triggers:** `Actor Run Finished`, `Task Run Finished`, `On new Apify Event`

```json
{
  "operation": "Run Actor",
  "actorId": "apify/web-scraper",
  "customInput": {"startUrls": [{"url": "https://example.com"}]},
  "timeout": 300,
  "memory": 512,
  "waitForFinish": true
}
```

⚠️ `waitForFinish: true` required for sequential workflows. Use `defaultDatasetId` from output for Get Items.
**Sources:** [Docs](https://docs.apify.com/platform/integrations/n8n) | [npm](https://www.npmjs.com/package/@apify/n8n-nodes-apify) | [GitHub](https://github.com/apify/n8n-nodes-apify)

### <a name="fireflies"></a>Fireflies
**Package:** `@firefliesai/n8n-nodes-fireflies` v2.1.0 | **Type:** `@firefliesai/n8n-nodes-fireflies.fireflies`
Meeting transcription & analysis | **Credential:** `firefliesApi`

**Resources:** `transcript`, `user`, `aiApp`, `askfred`, `audio`
**Operations:**
- `transcript`: `getTranscript`, `getTranscriptsList`, `getTranscriptSummary`, `getTranscriptAnalytics`, `getTranscriptAudioUrl`, `getTranscriptVideoUrl`
- `user`: `getCurrentUser`, `getUsers`
- `aiApp`: `getAIAppOutputs`
- `askfred`: `createThread`, `continueThread`, `getThread`, `getThreads`, `deleteThread`
- `audio`: `uploadAudio`

⚠️ **Breaking (v2.1.0):** `audio_url`/`video_url` fields removed from `transcript.get` response — use dedicated `getVideoUrl`/`getAudioUrl` operations instead.

```json
{"resource": "transcript", "operation": "get", "transcriptId": "={{$json.transcriptId}}"}
```

**Sources:** [npm](https://www.npmjs.com/package/@firefliesai/n8n-nodes-fireflies) | [GitHub](https://github.com/firefliesai/n8n-nodes-fireflies)

### <a name="firecrawl"></a>Firecrawl ⭐
**Package:** `@mendable/n8n-nodes-firecrawl` v2.1.0 | **Type:** `@mendable/n8n-nodes-firecrawl.firecrawl`
Website → clean markdown/HTML | **Credential:** `firecrawlApi`

**Resources:** `Scraping`, `Crawling`, `Agent`, `MapSearch`, `Account`, `Extract`, `Browser`, `Interact`
**Operations (37+):**
- `Scraping`: `scrape`, `batchScrape`, `batchScrapeStatus`, `batchScrapeErrors`, `cancelBatchScrape`
- `Crawling`: `crawl`, `getCrawlStatus`, `cancelCrawl`, `getCrawlErrors`, `crawlActive`, `crawlParamsPreview`
- `Agent`: `agent`, `agentAsync`, `getAgentStatus`
- `MapSearch`: `map`, `search`
- `Account`: `teamCreditUsage`, `creditUsageHistorical`, `teamTokenUsage`, `teamTokenUsageHistorical`, `teamQueueStatus`
- `Extract`: `extract`, `getExtractStatus`
- `Browser`: `browserCreate`, `browserExecute`, `browserList`, `browserDelete` *(new in v2.1.0)*
- `Interact`: `interact`, `interactStop` *(new in v2.1.0)*
**Options:** `formats` (markdown/html/links), `onlyMainContent`, `waitFor` (JS rendering delay), `sitemap` (`"include"` / `"only"` / `"skip"`)

⚠️ **Breaking (v2.0.1):** Sitemap parameter changed from `ignoreSitemap`/`sitemapOnly` booleans → `sitemap: "include"/"only"/"skip"` enum.

**AI Agent Tool Mode:** Set `usableAsTool: true` on the node to use Firecrawl as an AI Agent tool. Requires `N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true` env var and n8n >= 1.79.0.

```json
{"operation": "scrape", "url": "={{$json.url}}", "formats": ["markdown"], "onlyMainContent": true, "waitFor": 2000}
```

⚠️ Free tier: 500 pages/month
**Sources:** [npm](https://www.npmjs.com/package/@mendable/n8n-nodes-firecrawl) | [GitHub](https://github.com/mendableai/n8n-nodes-firecrawl)

### <a name="awork"></a>awork
**Package:** `n8n-nodes-awork` v0.1.61 | **Type:** `n8n-nodes-awork.awork`
Project management & time tracking | **Credential:** `aworkApi`

**Resources:** `project`, `projecttask`, `user`, `company`, `document`
**Operations:**
- `project`: `getall`, `get`, `post`, `getprojectstatuses`, `changeprojectstatus`, `gettaskstatuses`, `gettasklists`, `posttaskstatus`, `posttasklist`, `getcomments`
- `projecttask`: `gettasksofproject`, `get`, `post`, `changestatus`, `settaskcustomfield`, `addtag`, `comments`, `settaskassignee`, `gettypesofwork`
- `user`: `getall`, `get`
- `company`: `create`, `getall`, `get`
- `document`: `getall`, `get`, `getcontent`, `create`, `delete`

```json
{"resource": "projecttask", "operation": "post", "projectId": "={{$json.projectId}}", "taskName": "={{$json.taskName}}"}
```

**Sources:** [npm](https://www.npmjs.com/package/n8n-nodes-awork)

### <a name="close-crm"></a>Close CRM ⭐
**Package:** `n8n-nodes-close-crm` v1.5.7 | **Types:** `closeCrm`, `closeCrmTrigger`, `closeCrmWebhook`
Sales CRM automation | **Credential:** `closeCrmApi`

**Resources:** `contact`, `lead`, `opportunity`, `task`, `note`, `call`
**Triggers:** `lead.created`, `lead.updated`, `contact.created`, etc.

```json
{"resource": "lead", "operation": "create", "name": "={{$json.companyName}}", "contacts": [{"name": "={{$json.name}}", "emails": [{"email": "={{$json.email}}"}]}]}
```

**Sources:** [npm](https://www.npmjs.com/package/n8n-nodes-close-crm) | [n8n Community](https://community.n8n.io/t/183693)

### <a name="docx-extractor"></a>Docx Extractor
**Package:** `n8n-nodes-docx-extractor` v0.1.0 | **Type:** `n8n-nodes-docx-extractor.docxExtractor`
Extract text from .docx → HTML/Text/Markdown | **Credential:** None

```json
{"operation": "extract", "binaryPropertyName": "data", "extractMetadata": true, "outputFormat": "markdown"}
```

**Sources:** [GitHub](https://github.com/annhdev/n8n-nodes-docx-extractor)

### <a name="docxtemplater"></a>DocXTempler
**Package:** `n8n-nodes-docxtemplater-pdf-converter` v0.1.7 | **Type:** `n8n-nodes-docxtemplater-pdf-converter.docxTemplater`
Generate .docx/PDF from templates (`{variableName}` placeholders) | **Credential:** None

⚠️ Requires LibreOffice for PDF conversion

```json
{"operation": "generate", "templateBinaryProperty": "template", "data": "={{$json.templateData}}", "outputFormat": "pdf"}
```

**Sources:** [npm](https://www.npmjs.com/package/n8n-nodes-docxtemplater-pdf-converter) | [n8n Community](https://community.n8n.io/t/25175)

### <a name="easybill"></a>EasyBill
**Package:** `n8n-nodes-easybill` v1.1.1 | **Type:** `n8n-nodes-easybill.easybill`
German invoicing platform | **Credential:** `easybillApi`

⚠️ Work in progress - not completely finished

```json
{"resource": "invoice", "operation": "create", "customerId": "={{$json.customerId}}", "items": "={{$json.lineItems}}"}
```

**Sources:** [npm](https://www.npmjs.com/package/n8n-nodes-easybill) | [GitHub](https://github.com/paulkolle/n8n-easybill-node)

### <a name="mcp-community"></a>MCP Client (Community) ⚠️
**Package:** `n8n-nodes-mcp` v0.1.37 | **Type:** `n8n-nodes-mcp.mcp`
Model Context Protocol - connect to MCP servers | **Credential:** `mcpServer`

⚠️ CORE version: `nodes-langchain.mcpClientTool` in `@n8n/n8n-nodes-langchain`. This is COMMUNITY version.
**Transports:** STDIO (command-line), HTTP Streamable (recommended), SSE (deprecated)

**Operations:** `executeTool`, `getPrompt`, `listPrompts`, `listResources`, `listTools`, `readResource`

```json
{"operation": "executeTool", "serverUrl": "http://localhost:3000", "toolName": "search_web", "parameters": "={{$json.searchParams}}"}
```

**Sources:** [npm](https://www.npmjs.com/package/n8n-nodes-mcp) | [GitHub](https://github.com/nerding-io/n8n-nodes-mcp) | [MCP Protocol](https://modelcontextprotocol.io)

### <a name="pandadoc"></a>PandaDoc
**Package:** `n8n-nodes-pandadoc` v0.2.0 | **Types:** `pandadoc`, `pandadocTrigger`
Document automation & e-signature | **Credential:** `pandadocApi`

**Triggers:** `document_completed`, `document_signed`

```json
{"resource": "document", "operation": "create", "templateId": "={{$json.templateId}}", "recipients": [{"email": "={{$json.email}}", "role": "Signer"}], "tokens": "={{$json.documentData}}"}
```

**Sources:** [npm](https://www.npmjs.com/package/n8n-nodes-pandadoc) | [GitHub](https://github.com/nukleas/n8n-nodes-pandadoc)

### <a name="qdrant-community"></a>Qdrant (Community) ⚠️
**Package:** `n8n-nodes-qdrant` v0.2.1 | **Type:** `n8n-nodes-qdrant.qdrant`
Vector database for semantic search & RAG | **Credential:** `qdrantApi`

⚠️ CORE version: `nodes-langchain.vectorStoreQdrant` in `@n8n/n8n-nodes-langchain`. This is COMMUNITY version for direct API.

**Operations:** `insert`, `search`, `delete`, `upsert`, `createCollection`, `deleteCollection`

```json
{"operation": "search", "collectionName": "documents", "queryVector": "={{$json.queryEmbedding}}", "limit": 5, "scoreThreshold": 0.7}
```

**Sources:** [npm](https://www.npmjs.com/package/n8n-nodes-qdrant) | [GitHub](https://github.com/qdrant/n8n-nodes-qdrant) | [Qdrant Blog](https://qdrant.tech/blog/n8n-node/)

### <a name="credentials-x"></a>Run Node With Credentials X
**Package:** `n8n-nodes-run-node-with-credentials-x` v0.4.1 | **Type:** `n8n-nodes-run-node-with-credentials-x.runNodeWithCredentialsX`
Execute any node with dynamic credentials (advanced) | **Credential:** varies

⚠️ Advanced: Requires deep n8n knowledge. Can only use same credential type as original node.

```json
{"nodeType": "n8n-nodes-base.httpRequest", "credentialName": "={{$json.selectedCredential}}", "nodeParameters": {"url": "={{$json.apiUrl}}", "method": "POST"}}
```

**Sources:** [npm](https://www.npmjs.com/package/n8n-nodes-run-node-with-credentials-x) | [n8n Community](https://community.n8n.io/t/46486)

### <a name="soap"></a>SOAP Request
**Package:** `n8n-nodes-soap` v0.1.0 | **Type:** `n8n-nodes-soap.soapRequest`
Legacy SOAP API integration (SAP, Oracle, Dynamics) | **Credential:** `soapApi`

⚠️ Last updated 2 years ago. Alternative: `n8n-nodes-soaprequest` by team-carepay (actively maintained)

```json
{"wsdlUrl": "https://example.com/service?wsdl", "operation": "getCustomer", "parameters": {"customerId": "={{$json.customerId}}"}, "soapVersion": "1.2"}
```

**Sources:** [npm](https://www.npmjs.com/package/n8n-nodes-soap) | [Alternative](https://github.com/team-carepay/n8n-nodes-soaprequest)

### <a name="slack-socket"></a>Slack Socket Mode ⭐
**Package:** `@mbakgun/n8n-nodes-slack-socket-mode` v1.5.0 | **Type:** `@mbakgun/n8n-nodes-slack-socket-mode.slackSocketMode`
Real-time Slack event processing (extends core) | **Credential:** `slackApi`

⚠️ Requires Socket Mode enabled in Slack app settings. Extends CORE Slack node with real-time capabilities.

**Events:** 100+ including `message`, `reaction_added`, `app_mention`, `member_joined_channel`, `file_shared`

```json
{"operation": "listenToEvents", "events": ["message", "app_mention"], "channelFilter": "={{$json.channelId}}"}
```

**Sources:** [npm](https://www.npmjs.com/package/@mbakgun/n8n-nodes-slack-socket-mode) | [Core Slack](https://docs.n8n.io/integrations/builtin/app-nodes/n8n-nodes-base.slack/)

### <a name="notion-advanced"></a>Notion Advanced ⭐
**Package:** `n8n-nodes-notion-advanced` v1.2.35-beta | **Type:** `n8n-nodes-notion-advanced.notionAdvanced`
Enhanced Notion API (extends core) | **Credential:** `notionApi`

⚠️ Extends CORE Notion node. Features: Complete API v2022-06-28, all block types, rich text, AI Agent Tool support, advanced queries

```json
{"resource": "block", "operation": "create", "pageId": "={{$json.pageId}}", "blockType": "paragraph", "richText": [{"type": "text", "text": {"content": "={{$json.content}}"}}]}
```

**Sources:** [npm](https://www.npmjs.com/package/n8n-nodes-notion-advanced) | [Core Notion](https://docs.n8n.io/integrations/builtin/app-nodes/n8n-nodes-base.notion/)

## Usage Notes

**Always use Community Node if available.** For operations/parameters, check the service's API docs – most are simple REST wrappers.

**For AI:** Always check this file when user mentions community nodes. Use exact `nodeType` from above. Set `typeVersion: 1` unless specified. MCP kennt Community Nodes seit v2.32. Validierungswarnungen können trotzdem auftreten bei sehr neuen Packages. Document usage in `workflows/<workflow-name>/community-nodes.json`.

**Core vs Community:**
- **Qdrant**: Core (`nodes-langchain.vectorStoreQdrant`) for AI/Vector. Community (`n8n-nodes-qdrant`) for direct API.
- **MCP**: Core (`nodes-langchain.mcpClientTool`) for AI. Community (`n8n-nodes-mcp`) for direct MCP.
- **Slack/Notion**: Core nodes + Community extensions for enhanced features.

**Validation:** ✅ Core → MCP validates | ✅ Community → MCP validates (seit v2.32) | ✓ Final → Manual test in n8n UI

**Schema Status:**
- ✅ **cached** — Schema in `schemas/nodes/` committed. Offline validation via n8nac works.
- ⬜ **no offline schema** — n8nac does not index this node. Schema not pullable automatically. Use the `nodeType`, credential key, and example JSON in this file as reference. Manual test in n8n UI required.

**Adding New:** Include package, version, nodeType, use case, credential, example. Mark ⭐ if frequent. Note if extends core. Set schema status.

---

**Last Updated:** 2026-04-15 | **Total:** 15 verified community nodes + 2 core extensions | **Schemas cached:** 15/15 (all nodes)
