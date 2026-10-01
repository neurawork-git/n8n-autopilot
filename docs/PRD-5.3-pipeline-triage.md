# PRD 5.3 — Pipeline-Triage & Gate-Klassifikation

> Status: P0–P2 umgesetzt in 5.3.0 (Install-Test offen) · Auslöser: Session-Review 2026-07-27 ·
> Issues [#33](https://github.com/neurawork-git/n8n-autopilot/issues/33)–[#40](https://github.com/neurawork-git/n8n-autopilot/issues/40)

## Problem

Ein EXTEND-Lauf von `build-stack-v2` auf einen bestehenden Stack verbrauchte **83 Subagents / 67 min**
und bewegte den kritischen Pfad um **null**. Alles Zielrelevante entstand in den 57 min **nach** dem
Abschalten der Pipeline, per Hand: drei Edits, Publish in Reihenfolge, ein echter Ingest-Test.

Belege (Workflow-Journal `wf_d084f501-5c0`, 80 Results):

| Symptom | Beleg im Journal |
|---|---|
| classB-Fix-Loop dreht 4× auf einem Nicht-Bug | Results 51–64: Tester `classB` → Author `written:false` („placeholder test IDs, Class A") → Repush → identischer HTTP 400 |
| No-Op-Edits als `failed` → Stack-HALT | Results 24, 27, 30, 38: `written:false` mit „already fully present" |
| Voller Autoring-Zyklus für Deploy-Only-Fälle | 16 Sub-WFs komplett durchgejagt, ~12 waren `TRACKED` + fertig |
| Lauf nur durch Handpatch des Pipeline-Scripts beendet | gepatchte Script-Kopie im Scratchpad |

## Ursache (eine Zeile)

Die Pipeline hat **einen Gang** — vollen Autoring-Zyklus pro Workflow — und **keine Triage**, die vorher
fragt: wie groß ist das Delta, und was muss überhaupt bewiesen werden.

Drei strukturelle Folgen:

1. **Falsche Erfolgs-Invariante.** Ziel ist „jeder Sub-WF einzeln grün inkl. Live-Test mit
   Synthetik-Payload" statt „der Use-Case läuft einmal E2E". Deshalb Fake-Payload-Tests,
   Einzelaktivierungen — und der echte E2E-Pfad lief nie.
2. **Kein Spec-/Referenz-Input.** Die maßgebliche Spec lag im Repo, die Pipeline bekommt sie nicht.
   Subagents re-researchen Node-Contracts statt das bewährte Muster des Zwillings-Workflows zu
   mirrorn → No-Op-Edits, und ein echtes Requirement wurde fast gekippt.
3. **Gates sitzen alle autoring-seitig.** Die echten Blocker waren Umgebung: Credential-Grant-Typ
   (delegiert statt app-only → 403), Publish-Reihenfolge (Callee vor Caller), ein `$vars`-Gate,
   ein Producer der 0 Rows enqueued. Kein Gate kann diese Klasse sehen.

## Ziele

- Eine Fehlklassifikation kostet **≤ 1 Zyklus**, nicht 4.
- „Änderung schon drin" ist ein **Erfolg**, kein Stack-Stopp.
- Ein Stack-Lauf aktiviert **einmal, topologisch bottom-up**, statt pro WF einzeln.
- Spec + Referenz-Zwilling sind **Pipeline-Input**, nicht Zufallswissen des Modells.
- Nicht-Ziel: neues Orchestrator-Framework, Retry-Policies, Telemetrie. Kleinste Diffs.

## Umsetzung

### P0 — Kreisel & Fehlklassifikation (#33, #34, #35, #37)

| # | Änderung | Datei |
|---|---|---|
| 1 | classB-Loop liest das Author-Verdikt: `written:false` → `break` + Eskalation als `test-data-gap`/`classA`, kein Repush | `skills/build-workflow-v2/{build,edit}.workflow.js` |
| 2 | `AUTHOR_SCHEMA` erhält `noChangeNeeded`; Patch-Gate mappt das auf `status:'success', noop:true` und skippt Validate/Deploy/Test (Datei == Remote-Base, da Comprehend refresht hat) | `edit.workflow.js`, `agents/n8n-author.md` |
| 3 | `TEST_SCHEMA.outcome` erhält `test-data-gap`; Tester klassifiziert externes 4xx aus Platzhalter-Payload als solches, nie als `classB` | `{build,edit}.workflow.js`, `agents/n8n-tester.md` |
| 4 | Nach eigener Aktivierung re-baselinen: Deployer bekommt den Hinweis, dass die Pipeline `activate` gefahren hat → `fetch` vor Repush, statt Falsch-Drift in `keep-current` zu eskalieren | `{build,edit}.workflow.js`, `agents/n8n-deployer.md` |

### P1 — Stack-Ebene (#36, #39, #40)

| # | Änderung | Datei |
|---|---|---|
| 5 | Neue Schlussphase `Activate`: topologisch bottom-up (Callees vor Callern), nicht pro Sub-WF. Kinder werden mit `deferActivation`/`deferTest` gebaut | `skills/build-stack-v2/stack.workflow.js`, `{build,edit}.workflow.js` |
| 6 | Aktivierungs-Regel um die echte Ursache ergänzen: Callee nicht published ≠ kaputter Workflow | `agents/n8n-tester.md`, `CLAUDE.md` |
| 7 | Deploy-Only-Fast-Path: über P0-2 erreicht — ein bereits erfüllter Change kostet Comprehend+Patch (2 Agents) statt 7 | — |
| 8 | `specPath` + `referenceWorkflow` als Stack-Args, injiziert in Architect-/Author-Prompts („mirror das belegte Muster, nicht neu ableiten") | `stack.workflow.js` |

### P1b — Feedback-Capture (im Review dieser Session gefunden, kein Issue — gleich mitgefixt)

| # | Änderung | Datei |
|---|---|---|
| 10 | Capture lief nur auf `SessionEnd` (feuert nur bei sauberem Ende) → lange/resumte Sessions lieferten **nichts**: nachweisbare Lücke 01.07.–27.07., 0 Events trotz Mehrstunden-Sessions. Jetzt zusätzlich `PreCompact` + `SessionStart(resume/compact)`, `startup`/`clear` übersprungen; auslösendes Event steht in `endReason` | `hooks/hooks.json`, `scripts/capture-feedback.sh` |
| 11 | `n8nacVersion` war in **jedem** Event `""` (las `<cwd>/node_modules/n8nac`, existiert bei npx nie) → Fallback auf höchste Version im npx-Cache, ohne Spawn | `scripts/capture-feedback.sh` |

Verifiziert per Payload-Probe (vier Varianten): `clear` ✓, `precompact:auto` ✓, `start:resume` ✓,
`startup` korrekt übersprungen — alle mit `n8nacVersion='2.5.0'`.

### P2 — Doku (#38)

| # | Änderung | Datei |
|---|---|---|
| 9 | `credential create`-Recipe für `oAuth2Api`/`clientCredentials` inkl. zwei Fallen: `allowedHttpRequestDomains:"none"` macht die Cred in HTTP-Request-Nodes unbrauchbar; es gibt kein `credential update` (delete + recreate + Referenzen umschreiben) | `skills/n8nac-cheatsheet/SKILL.md` |

## Abnahme

- `node scripts/test-pipeline-gates.mjs` grün: stubbt `agent()`/`log()`/`phase()` und beweist
  (a) No-Op-Patch → `status:'success', noop:true` ohne Deploy-Call,
  (b) classB + `written:false` → genau **ein** Fix-Versuch, kein Repush.
- Version `.claude-plugin/plugin.json` → `5.3.0`; Install-Test nach `plugin-testing`-Skill
  (commit → push → install aus Repo → `/n8n-autopilot:check-mcps`).
