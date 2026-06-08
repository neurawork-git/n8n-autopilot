<div align="right">

[English](README.md) · **Deutsch**

</div>

<div align="center">

# 🤖 n8n-autopilot

**Ein Claude Code Plugin, das natürlichsprachliche Prompts in validierte, deployte n8n-Workflows verwandelt.**

[![Version](https://img.shields.io/badge/version-4.10.0-blue.svg)](CHANGELOG.md)
[![Lizenz: MIT](https://img.shields.io/badge/lizenz-MIT-green.svg)](LICENSE)
[![Node.js](https://img.shields.io/badge/node-%E2%89%A518-339933.svg?logo=node.js&logoColor=white)](https://nodejs.org)
[![n8nac](https://img.shields.io/badge/n8nac-2.3.6%20(min%202.3.0)-ff6d5a.svg)](https://www.npmjs.com/package/n8nac)
[![Claude Code](https://img.shields.io/badge/claude%20code-plugin-d97757.svg)](https://docs.claude.com/claude-code)

```
/n8n-autopilot:build-workflow "Webhook empfängt Stripe-Zahlung → updated Postgres → schickt Slack-Alert"
```

</div>

Claude recherchiert die exakten Node-Parameter, schreibt validiertes TypeScript, pusht auf deine n8n-Instanz und testet live — ohne dass du die n8n-UI anfassen musst.

---

## Inhalt

- [Warum das Plugin existiert](#warum-das-plugin-existiert)
- [Was du machen kannst](#was-du-machen-kannst)
- [So funktioniert die Build-Pipeline](#so-funktioniert-die-build-pipeline)
- [Skill-Referenz](#skill-referenz)
- [Setup](#setup)
- [Workflow-Format](#workflow-format)
- [Sync: Lokal ↔ n8n](#sync-lokal--n8n)
- [Plugin-Struktur](#plugin-struktur)
- [Dokumentation](#dokumentation)
- [Changelog](CHANGELOG.md)

---

## Warum das Plugin existiert

n8n-Workflows manuell zu bauen bedeutet:
- Node-Parameter-Namen in Docs nachschlagen
- Credential-Key-Formate raten
- Kaputtes JSON pushen und zur Laufzeit debuggen

Dieses Plugin gibt Claude Code tiefes n8n-Wissen — 537+ Node-Schemas, 7.700 Community-Templates, Expression-Validierung, Live-Testing — sodass Production-Workflows beim ersten Anlauf korrekt sind.

---

## Was du machen kannst

### Workflows aus einer Beschreibung bauen

```
/n8n-autopilot:build-workflow "Jeden Morgen um 8 Uhr offene GitHub-Issues holen, nach Label 'urgent' filtern, Zusammenfassung an Slack posten"
```

```
/n8n-autopilot:build-workflow "HTTP-Webhook empfängt Kundendaten, validiert Email, upsertet in Postgres, gibt Bestätigung zurück"
```

```
/n8n-autopilot:build-workflow "RSS-Feed-Monitor: stündlich prüfen, neue Items erkennen, mit GPT-4o-mini zusammenfassen, Digest per Mail senden"
```

Claude führt automatisch eine 3-Phasen-Pipeline aus:
1. **Recherche** — findet exakte Node-Typen und -Parameter via n8nac (offline, ~5 ms pro Node)
2. **Schreiben + Validieren** — schreibt Decorator-TS, validiert gegen 537+ Schemas, pusht zu n8n
3. **Deploy + Test** — testet via Test-URL (keine Aktivierung nötig), klassifiziert Fehler, fixt und versucht erneut

### Neues Repo in einem Befehl bootstrappen

```
/n8n-autopilot:init-repo mein-kunde
```

Scaffolded das Verzeichnis-Layout, schreibt eine plugin-kompatible `CLAUDE.md`, fährt den n8nac-≥-2.3-Setup-Flow (`env add` + `env auth set` + `env use`), zieht Node-Schemas und verifiziert — sodass der erste `build-workflow`-Aufruf sofort läuft.

### Bestehende Workflow-Datei deployen

```
/n8n-autopilot:deploy workflows/mein-workflow.workflow.ts
```

### Credential-IDs entdecken oder reparieren

```
/n8n-autopilot:sync-credentials                    # listet Live-Credentials
/n8n-autopilot:sync-credentials --fix-workflows    # schreibt stale IDs in workflows/ neu, gematcht über Credential-Namen
```

`--fix-workflows` ist genau das, was der SessionStart-Hook `check-credential-freshness` automatisch triggert, wenn er stale Referenzen erkennt.

### Workflows inventarisieren

```
/n8n-autopilot:inventory
```

Aggregiert jeden Node-Typ, jedes LLM-Modell, jede Credential und jeden Trigger über `workflows/**/*.workflow.ts` in `docs/INVENTORY.md`. Nützlich beim Planen neuer Workflows, beim Onboarding in ein bestehendes Projekt oder beim Auditieren einer Instanz.

### DataTable-Ressourcen verwalten

```
/n8n-autopilot:data-tables
```

n8nac hat keinen DataTable-Subcommand. Dieser Skill dokumentiert jeden `/api/v1/data-tables`-Endpoint (Tabellen, Spalten, Zeilen) mit kopierfähigen curl-Rezepten — der einzige für Claude erreichbare REST-API-Pfad nach dem PreToolUse curl-Block.

### MCP-Health prüfen

```
/n8n-autopilot:check-mcps
```

Zwei-Schicht-Check: Infrastruktur-Erreichbarkeit (Endpoints, Tokens) UND Tool-Registrierung im aktiven Claude-Kontext. Nach Setup oder wenn MCP-Tools nicht verfügbar wirken.

### Bei n8n-Spezifika nach Hilfe fragen

```
Wie greife ich auf Webhook-Daten in einem Code-Node zu?
```
```
Wie ist die korrekte Expression-Syntax, um Daten aus einem vorigen Node zu referenzieren?
```
```
Warum schlägt meine IF-Node-Operator-Validierung fehl?
```

Die Knowledge-Skills aktivieren sich automatisch — JavaScript/Python Code-Nodes, Expression-Syntax, Validierungs-Fehler, Workflow-Patterns.

### Feedback zur Autopilot-Erfahrung geben

```
/n8n-autopilot:feedback
```

Das Plugin lernt aus echter Nutzung. Ein `SessionEnd`-Hook erfasst still und ohne PII die Häufigkeit
von Reibungssignalen (Konflikt-Auflösungs-Churn, Non-HTTP-Test-Umwege, Validierungs-Schleifen, …) in
einen gitignorierten lokalen Speicher; ein `SessionStart`-Hinweis erinnert dich an ausstehendes
Feedback. `/n8n-autopilot:feedback` führt ein kurzes Interview, `/n8n-autopilot:feedback sync` schiebt
alles zentral als ein GitHub-Issue (mit Bestätigung — du prüfst vorher jeden Record). Erfasste Records
enthalten nur Counts + den Repo-Namen, niemals Kundendaten.

---

## So funktioniert die Build-Pipeline

```
Phase 0                   Phase 1                         Phase 2
Recherche                 Schreiben + Validieren + Push   Deploy + Test
────────────────────────  ──────────────────────────────  ────────────────────────
n8n-researcher (Haiku)    Claude schreibt .workflow.ts    npx n8nac test-plan
                          workflow-reviewer (Sonnet)      npx n8nac test [--query]
search_n8n_knowledge()    npx n8nac skills validate       ← exit 0 = Class A (informieren)
                            --strict --json               ← exit 1 = Class B (fixen)
get_n8n_node_info()       fix → re-validate Loop
search_n8n_workflow_      npx n8nac push --verify         npx n8nac workflow activate
  examples()              ← Push + Remote-Check in 1 →   npx n8nac execution get

keine n8n-API nötig       Decorator-TS Format,            n8n-API erforderlich
                          niemals JSON von Hand
```

**Fehler-Klassifikation nach Live-Test:**

| Exit | Klasse | Bedeutung | Was passiert |
|------|--------|-----------|--------------|
| 0 | Success | Workflow lief korrekt | Fertig |
| 0 | Class A | Fehlende Credentials/Modell | Wird an User gemeldet, nicht blockiert |
| 1 | Class B | Verdrahtungs-Fehler (Expression falsch, falsches Feld) | Claude fixt → re-validiert → re-pusht → re-testet |
| 1 | Fatal | Kein Trigger, Workflow nicht gefunden | Wird an User gemeldet |

**MCP-Trigger-Workflows:** Workflows mit `@n8n/n8n-nodes-langchain.mcpTrigger` exponieren einen MCP-Endpoint, der nur in der *publizierten* Version erreichbar ist. n8nac kann Drafts nicht publizieren — nach jedem Push zeigt die Deploy-Pipeline einen prominenten Hinweis, dass der User in der n8n-UI auf "Publish" klicken muss.

**Non-HTTP-Trigger (schedule, manual, errorTrigger):** n8nac kann diese nicht auslösen. Die `build-workflow`-Pipeline (Path B) stoppt nach dem Push und prompted den User, in der n8n-UI auf "Execute Workflow" zu klicken; sobald eine Execution-ID gemeldet wird, inspiziert Claude die Ergebnisse via `npx n8nac execution get --include-data`.

---

## Skill-Referenz

### Slash-Commands

| Command | Was er tut |
|---------|-----------|
| `/n8n-autopilot:init-repo [target]` | Scaffold eines frischen n8n-Workflow-Repos: Verzeichnis-Layout, CLAUDE.md, n8nac-Config, Schemas — in einem Schritt |
| `/n8n-autopilot:build-workflow "beschreibung"` | Voll-Pipeline: recherchieren → schreiben → validieren → pushen → live-testen |
| `/n8n-autopilot:deploy <pfad>` | Push + optional Aktivierung eines bestehenden `.workflow.ts` |
| `/n8n-autopilot:pull-schemas [--packages …]` | Node-Schemas für Offline-Validierung aktualisieren (gezielt via `--packages`) |
| `/n8n-autopilot:sync-credentials [--fix-workflows]` | Live-Credential-IDs entdecken; mit `--fix-workflows` werden stale IDs in lokalen Dateien neu geschrieben |
| `/n8n-autopilot:inventory` | Node-Typ- / LLM- / Credential-Nutzung aus lokalen Workflows in `docs/INVENTORY.md` aggregieren |
| `/n8n-autopilot:data-tables` | DataTable-Ressourcen (Tabellen, Spalten, Zeilen) via n8n-REST-API verwalten (curl-Carve-out) |
| `/n8n-autopilot:check-mcps` | n8nac-MCP-Verbindung prüfen (Infrastruktur + Tool-Registrierung) |
| `/n8n-autopilot:test-manual <id>` | Non-HTTP-Trigger-Workflow testen (schedule/manual/errorTrigger): löst die UI-URL auf, wartet auf die execution-id, inspiziert den Run |
| `/n8n-autopilot:feedback [show\|sync]` | Autopilot-Prozess-Feedback erfassen (Interview); `sync` schiebt ausstehende Records zentral als GitHub-Issue (mit Bestätigung) |

### Knowledge-Skills (auto-aktiviert, direkt aufrufbar)

**Workflow-Bau:**

| Skill | Deckt ab |
|-------|----------|
| `n8n-workflow-patterns` | 5 Patterns: Webhook-Processing, HTTP-API, Datenbank-Ops, AI-Agent, Scheduled Tasks |
| `n8n-node-configuration` | Operation-aware Config, Property-Dependencies, Pflichtfelder pro Node-Typ |
| `n8n-validation-expert` | Fehlertypen, False Positives, Expression-Validierung, Auto-Sanitisierung, Bulk-Fixes |
| `n8n-orchestration-patterns` | Fan-out/Fan-in, parallele Sub-Workflows (Branch-Split-Falle, `executionOrder: v0`, DataTable-Fan-In), Batch + Fast-Return-Webhook |
| `n8n-structured-extraction` | LLM-Extraktion/Klassifikation via echtem JSON-Schema (Information Extractor / Text Classifier), nicht Agent+Prompt |

**Code-Nodes:**

| Skill | Deckt ab |
|-------|----------|
| `n8n-code-javascript` | `$input`/`$json`/`$node`, `$helpers.httpRequest()`, DateTime (Luxon), Return-Format, Top-5-Fehler |
| `n8n-code-python` | `_input`/`_json`, nur Standard-Library (kein requests/pandas), Workarounds |
| `n8n-expression-syntax` | `={{ }}`-Format, Webhook-`.body`-Struktur, `$node["Name"]`-Referenzen, häufige Fehler |

---

## Setup

### Voraussetzungen

- **Node.js 18+**
- **n8nac ≥ 2.3.0** (auto-installiert via `npx`; das Plugin erzwingt die Mindestversion)
- **Claude Code**
- **Laufende n8n-Instanz** — lokal (`docker run -p 5678:5678 n8nio/n8n`) oder [n8n Cloud](https://app.n8n.cloud)
- **n8n-API-Key** — n8n-UI → Settings → n8n API → Create API Key

### 1. Beide Plugins installieren

n8n-autopilot stützt sich auf Etienne Lescots `n8n-as-code` Plugin für die `n8n-architect`-Skill (Schema-Research + Authoring-Regeln + AI/LangChain-Regeln). Beide installieren:

```bash
# n8n-autopilot — Workflow-Lifecycle-Orchestrierung
claude plugin marketplace add neurawork-git/n8n-autopilot
claude plugin install n8n-autopilot@n8n-autopilot

# n8n-as-code (Companion) — n8n-Knowledge-Base + Authoring-Regeln
claude plugin marketplace add EtienneLescot/n8n-as-code
claude plugin install n8n-as-code@n8nac-marketplace
```

**Für Teams:** in `.claude/settings.json` committen — Teammitglieder bekommen beide Plugins automatisch:

```json
{
  "extraKnownMarketplaces": {
    "n8n-autopilot": {
      "source": { "source": "github", "repo": "neurawork-git/n8n-autopilot" }
    },
    "n8nac-marketplace": {
      "source": { "source": "github", "repo": "EtienneLescot/n8n-as-code" }
    }
  },
  "enabledPlugins": {
    "n8n-autopilot@n8n-autopilot": true,
    "n8n-as-code@n8nac-marketplace": true
  }
}
```

> **Keine `.mcp.json` nötig.** n8n-autopilot 4.x ist CLI-only — alle Schema-Recherche läuft über `npx n8nac skills …`. Der `mcp__n8n-as-code__*` Namespace aus älteren Versionen hatte nie eine stabile Upstream-Quelle (npm `n8nac mcp` ist kaputt; Etiennes Plugin liefert Skill-Knowledge, keinen MCP-Server).

### 2. Environment anlegen und aktivieren (n8nac ≥ 2.3)

> **Bezugsversion n8nac: 2.3.6.** Ab 2.3.x ist `workspace` read-only (nur `status`/`get`). Alle Instanz- und Projekt-Konfiguration liegt auf `env`. Die alten Commands `init` / `init-auth` / `init-project` sowie alle schreibenden `workspace`-Mutators wurden entfernt.

```bash
# 2a. Environment anlegen (Instanz-URL + Sync-Folder in einem Schritt)
npx n8nac env add Prod --base-url "$N8N_API_URL" --workflows-path workflows

# 2b. API-Key hinterlegen (über stdin — niemals in der Shell-History)
printf "%s" "$N8N_API_KEY" | npx n8nac env auth set Prod --api-key-stdin

# 2c. Environment aktivieren
npx n8nac env use Prod

# Optional: Workspace auf ein bestimmtes n8n-Projekt eingrenzen
npx n8nac env update Prod --project-name Personal
# oder beim Anlegen direkt: env add Prod ... --project-name Personal
```

**Migration von n8nac < 2.3?** Es gibt keinen `migrate`-Befehl mehr — der Workspace-Storage ist v4-nativ. Eine verwaiste `./n8nac-config.json` im Repo einfach manuell löschen; die Config liegt jetzt im User-Home (`~/n8nac-config.json` + `~/.n8n-manager/`).

### 3. Node-Schemas ziehen

```
/n8n-autopilot:pull-schemas
```

Schemas werden nicht committed — sie sind instanz-spezifisch (Community-Nodes variieren pro User). Dieser Schritt befüllt `schemas/nodes/` mit den Core-Nodes plus den auf deiner n8n-Instanz installierten Community-Nodes. Erneut ausführen, wann immer du einen neuen Community-Node installierst oder beim SessionStart Stale-Warnungen siehst.

### 4. Verifizieren, dass alles funktioniert

```
/n8n-autopilot:check-mcps
```

(oder läuft automatisch via SessionStart-Hook beim nächsten Öffnen von Claude Code in diesem Repo)

Prüft Node.js, n8nac-CLI-Version (min 2.3.0, Referenz 2.3.6), Workspace-Binding via `n8nac workspace status`, Live-n8n-Erreichbarkeit, Companion-Plugin aktiviert, Community-Node-Schema-Coverage. Fixe Fehler, bevor du Workflows baust.

---

## Workflow-Format

Workflows sind **Decorator-TS** (`.workflow.ts`) — kein rohes JSON. Claude schreibt das; du editierst es nie manuell.

```typescript
@workflow({ name: "Stripe → Postgres → Slack", settings: { errorWorkflow: "" } })
class StripePaymentWorkflow {

  @trigger({ type: "n8n-nodes-base.webhook", parameters: { path: "stripe-payment", httpMethod: "POST" } })
  Webhook = {};

  @node({ type: "n8n-nodes-base.postgres", typeVersion: 2.5, parameters: {
    operation: "upsert", schema: { __rl: true, value: "public", mode: "list" },
    table: { __rl: true, value: "payments", mode: "list" },
  }})
  UpdateDatabase = {};

  @node({ type: "n8n-nodes-base.slack", typeVersion: 2.2, parameters: {
    authentication: "oAuth2", resource: "message", operation: "post",
    select: "channel", channelId: { __rl: true, mode: "id", value: "#payments" },
    text: "={{ $json.body.amount }} erhalten von {{ $json.body.customer }}",
  }})
  SendAlert = {};

  @links()
  flow() { return this.Webhook.out().to(this.UpdateDatabase).to(this.SendAlert); }
}
```

---

## Sync: Lokal ↔ n8n

```bash
npx n8nac list                                         # Sync-Status anzeigen: TRACKED / CONFLICT / LOCAL-ONLY / REMOTE-ONLY (ohne archivierte)
npx n8nac list --include-archived --json               # inkl. archivierter; strukturierter Output für Agents
npx n8nac list --search <q> --sort name --limit 20     # filtern, sortieren, paginieren; --local / --remote Scope
npx n8nac find <query>                                 # schnelle Fuzzy-Suche über Workflows
npx n8nac pull <workflowId>                            # von n8n als .workflow.ts herunterladen
npx n8nac push workflows/<name>.workflow.ts            # zu n8n hochladen
npx n8nac push workflows/<name>.workflow.ts --verify   # hochladen + Remote-State in einem Schritt validieren
npx n8nac resolve <id> --mode keep-current             # Konflikt: lokale Version gewinnt
npx n8nac resolve <id> --mode keep-incoming            # Konflikt: Remote-Version gewinnt

npx n8nac test <workflowId> --data '{"key":"value"}'   # Live-Test via Test-URL (POST/Body)
npx n8nac test <workflowId> --query '{"key":"value"}'  # Live-Test via Test-URL (GET/Query-Params)
npx n8nac test <workflowId> --prod                     # Test via Produktions-URL (Workflow muss aktiv sein)

npx n8nac workflow credential-required <id>            # prüft, ob alle Credentials vorhanden sind (exit 0 = ok, exit 1 = fehlend)
npx n8nac workflow activate <id>                       # Workflow für Produktion aktivieren
npx n8nac workflow deactivate <id>                     # Workflow deaktivieren

npx n8nac execution list --workflow-id <id>            # Executions eines Workflows auflisten
npx n8nac execution list --status error --json         # nach Status filtern, maschinen-lesbarer Output
npx n8nac execution get <execId> --include-data        # vollständige Execution-Daten zum Debuggen

npx n8nac credential list                              # alle Credentials auflisten
npx n8nac credential schema <type>                     # Pflichtfelder für einen Credential-Typ zeigen

npx n8nac fetch <workflowId>                           # Remote-State explizit abrufen
npx n8nac update-ai                                    # AGENTS.md + AI-Kontext regenerieren

npx n8nac skills validate <file> --strict --json       # lokale Validierung (strukturierter Output für Agents)
npx n8nac skills node-schema <name> --json             # schnelles TypeScript-Snippet für einen Node
npx n8nac skills node-info <name> --json               # vollständige Node-Info
npx n8nac skills examples search/list/info/download    # Community-Templates browsen + herunterladen
npx n8nac skills list --nodes --docs --guides          # verfügbare Referenzen enumerieren

npx n8nac env list/add/update/pin/remove               # Workspace-Environments verwalten (mehrere n8n-Instanzen)
npx n8nac env add <name> --base-url <url> --workflows-path workflows   # neues Environment anlegen
npx n8nac env auth set <name> --api-key-stdin          # API-Key für ein Environment hinterlegen
npx n8nac env use <name>                               # aktives Environment wechseln (Alias: env pin)
npx n8nac env update <name> --project-name <n>         # Environment-Konfiguration aktualisieren (z. B. Projekt)
npx n8nac workspace status --json                      # effektiver Workspace-Kontext (read-only, autoritativ)
npx n8nac setup --mode connect-existing --host <url> --api-key-stdin   # Facade-Runtime-Modus wählen (optional)

npx n8nac credentials recipes --json                   # Shared-Credential-Recipe-Katalog (openai-native, slack-oauth, …)
npx n8nac credentials inventory --json                 # lokale Credential-Readiness-Inventory
npx n8nac credentials ensure <recipeId> --host <url> --api-key-stdin   # Credential aus Recipe erzeugen
npx n8nac credentials test <id-or-recipeId>            # Credential live verifizieren

npx n8nac workflow present <id> --json                 # User-facing URL eines Workflows auflösen (nie selber zusammenbauen)
```

---

## Plugin-Struktur

```
n8n-autopilot/
├── .claude-plugin/
│   ├── plugin.json                  Plugin-Manifest (v3.6.1)
│   └── marketplace.json             Marketplace-Eintrag
│
├── skills/
│   ├── init-repo/                   /n8n-autopilot:init-repo  (+ scripts/, assets/)
│   ├── build-workflow/              /n8n-autopilot:build-workflow
│   ├── deploy/                      /n8n-autopilot:deploy
│   ├── pull-schemas/                /n8n-autopilot:pull-schemas
│   ├── sync-credentials/            /n8n-autopilot:sync-credentials
│   ├── inventory/                   /n8n-autopilot:inventory
│   ├── data-tables/                 /n8n-autopilot:data-tables
│   ├── check-mcps/                  /n8n-autopilot:check-mcps
│   ├── n8n-node-configuration/      Knowledge: Node-Config + Property-Dependencies (+ references/)
│   ├── n8n-validation-expert/       Knowledge: Validierungs-Fehler + Expression-Validierung (+ references/)
│   ├── n8n-workflow-patterns/       Knowledge: 5 Architektur-Patterns (+ references/)
│   ├── n8n-code-javascript/         Knowledge: JS-Code-Node-Referenz
│   ├── n8n-code-python/             Knowledge: Python-Code-Node-Referenz
│   └── n8n-expression-syntax/       Knowledge: Expression-Syntax + häufige Fehler
│
├── agents/
│   ├── n8n-researcher.md            Phase 0: Node-Discovery (Haiku)
│   └── workflow-reviewer.md         Phase 1: Pre-Deploy Code-Review (Sonnet)
│
├── hooks/hooks.json                 SessionStart: setup-check + schema-version + credential-freshness
│                                    PreToolUse: blockiert direkten REST-API-Zugriff (Carve-out für /api/v1/data-tables)
│                                                + auto-guard `availableInMCP` Workflow-Setting
│
├── scripts/
│   ├── setup-check.sh               SessionStart 1: Config + Erreichbarkeit + Community-Node-Coverage + Inventory-Freshness
│   ├── check-schema-versions.sh     SessionStart 2: stale Community-Node-Schemas
│   ├── check-credential-freshness.sh   SessionStart 3: stale Credential-Refs in Workflows
│   ├── check-installed-nodes.sh     Indirekt: installierte Nodes ohne Schema-Cache
│   ├── check-inventory-freshness.sh    Indirekt: INVENTORY.md-Staleness (informational)
│   └── ensure-mcp-trigger-setting.sh   PreToolUse bei `n8nac push`: schützt `availableInMCP`
│
├── schemas/nodes/                   Gecachte Node-Schemas (gitignored, befüllt durch /pull-schemas)
├── docs/                            Architektur, MCP-Guide, Credentials, Community-Node-Registry, Inventory
└── CHANGELOG.md                     Release-Historie
```

---

## Dokumentation

| Dokument | Inhalt |
|----------|--------|
| [docs/OVERVIEW.md](docs/OVERVIEW.md) | Einseiter: wie wir n8nac nutzen und was das Plugin draufpackt |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System-Design, Workflow-Lifecycle, Sync-Modell |
| [docs/CREDENTIALS.md](docs/CREDENTIALS.md) | Credential-Typen, IDs, Nutzung in Decorator-TS |
| [docs/COMMUNITY_NODES.md](docs/COMMUNITY_NODES.md) | 15 verifizierte Community-Nodes mit Schemas |
| [docs/MCP.md](docs/MCP.md) | MCP-Integration: n8n-as-code Setup, Tokens, Troubleshooting |
| [docs/INVENTORY.md](docs/INVENTORY.md) | Beispiel-Output von `/n8n-autopilot:inventory` |
| [CHANGELOG.md](CHANGELOG.md) | Release-Historie |
