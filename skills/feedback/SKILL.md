---
name: feedback
description: Review the current n8n-autopilot session for learnings (operational friction + workflow design anti-patterns), strip all PII, and push the redacted insights centrally via the plugin's ingest webhook (they land as batch comments on the public rollup issue). Side-effecting on `sync`/`review`-push — shows the redacted result and requires explicit confirmation.
argument-hint: "[review | interview | show | sync]"
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash(bash:*), Bash(node:*), Bash(curl:*)
---

# Autopilot Feedback — Review, Redact, Push

The plugin learns from real usage. This skill reviews a session, **removes anything
data-protected**, and pushes the distilled learnings centrally so the same friction does not recur
across customers. Local stores live in the consumer repo under `.n8n-autopilot/feedback/`
(gitignored): `events.ndjson` (auto-captured signal counts from the SessionEnd hook) +
`process.ndjson` (review/interview output). The deterministic PII gate lives in
`scripts/redact-check.js`.

Parse `$ARGUMENTS`:
- empty / `review` → **Review & push** (default, the one-shot)
- `interview` → short manual Q&A only
- `show` → list pending records
- `sync` → push existing pending records (re-runs the PII gate)

> **PII is non-negotiable.** Consumer repos contain customer data. Everything that
> leaves the machine is (1) LLM-redacted to neutral insights and (2) passed through a deterministic
> allowlist gate (`redact-check.js`) that BLOCKS emails, paths, URLs, long digit runs, tokens, and
> configured customer names. Counts + repo basename only; never transcript text or workflow content.

---

## Review & push (default)

### 0. Resolve the plugin root once

`$CLAUDE_PLUGIN_ROOT` is expanded inside `hooks.json` commands only — in the Bash tool it is EMPTY,
and every `node "$CLAUDE_PLUGIN_ROOT/…"` call below then fails with `MODULE_NOT_FOUND` on a path
under the shell root (#74, #100). Set it from the skill's base directory (the "Base directory for
this skill" line Claude Code printed when this skill loaded — its plugin root is two levels up):

```bash
PR="${CLAUDE_PLUGIN_ROOT:-<plugin root, e.g. ~/.claude/plugins/marketplaces/n8n-autopilot>}"
test -f "$PR/skills/feedback/scripts/record.js" || echo "wrong plugin root: $PR"
```

Use `"$PR"` in every command below.

### 1. Resolve the session transcript

```bash
node "$PR/skills/feedback/scripts/latest-transcript.js" --workspace .
```

Use the printed path. (If it errors — no transcript — fall back to reviewing `events.ndjson` only.)

### 2. Gather auto-captured signals

Read `.n8n-autopilot/feedback/events.ndjson` — these are the SessionEnd hook's NON-PII friction
counts (the 11 operational classes + `memory_oom` + `continue_on_fail`). Summarize the totals.

### 3. Measure file-level design quality (accurate — read the actual workflows)

These design anti-patterns are NOT in the transcript counts; measure them from the real files.
Use Grep/Read over `workflows/**/*.workflow.ts`:

- **Code-overuse (D1)** — count `n8n-nodes-base.code` vs native `if`/`switch`/`filter`. Flag Code
  nodes that only branch or remap (a native node would do it). Report the ratio.
- **Missing descriptions (D4)** — `@workflow({...})` without a `description`; key nodes without notes.
- **Overlapping nodes (D5)** — node `position` pairs within ~80px on both axes (unreadable canvas).
- (Memory/OOM + continueOnFail already come from step 2's signals.)

### 4. Qualitative pass (targeted, not a full dump)

Skim the transcript for process pain the counts miss (repeated dead-ends, manual detours, unclear
errors). Keep it to a few concrete, **generalizable** observations — NOT a play-by-play.

### 5. Compose REDACTED, TYPED finding records — one per concrete problem

**A finding is the actionable unit: one finding = one GitHub issue.** Do NOT write one blob record —
write one finding per distinct problem, each answering: what went wrong, where, what was expected,
what would fix it. Neutral phrasing, **no customer names, no file paths, no workflow content, no
values, no URLs.** Node types (`n8n-nodes-base.github`) and n8nac commands (`n8nac push`) are safe
and REQUIRED context — put them in `area`.

```bash
node "$PR/skills/feedback/scripts/record.js" '{
  "kind": "finding",
  "type": "schema-gap|cli-friction|validation-loop|mcp-detour|credential-gap|doc-gap|design-antipattern|bug|other",
  "severity": "low|medium|high",
  "area": "<node type or n8nac command>",
  "title": "<one line — becomes the issue title>",
  "observed": "<what actually happened, incl. exact error phrase if non-PII>",
  "expected": "<what should have happened>",
  "suggestion": "<concrete fix idea>",
  "signals": { "<signal-class>": N }
}'
```

`type`, `title`, `observed` are required (record.js enforces). Attach the session's relevant signal
counts as `signals` evidence. Repeat per problem — 3 problems = 3 findings = 3 issues.

### 6. Run the deterministic PII gate (show the user)

```bash
node "$PR/skills/feedback/scripts/redact-check.js" .n8n-autopilot/feedback/process.ndjson
```

- **OK** → proceed.
- **BLOCKED** → the gate lists the offending field. Re-redact that field (neutralize it) and rewrite
  the record, then re-run. NEVER bypass the gate.

### 7. Confirm — one line per finding, then a multiple-choice prompt

Do **not** dump the records verbatim. With three or more findings that is a wall of text nobody reads,
and an unread confirmation is not consent. Render a compact table:

```
| # | sev | type | title |
|---|-----|------|-------|
| 1 | high   | bug          | push rejects a validated file … |
| 2 | medium | cli-friction | extend mode re-builds unchanged … |
```

Then state the target in **one** line — *"pushes N finding(s) as N public GitHub issues on
`neurawork-git/n8n-autopilot`; customer/repo name stripped, `reporter` = your OS username included by
design"* — and ask via **`AskUserQuestion`**, not free text:

- **Alle pushen** (N findings)
- **Auswählen** — then list the numbers to push
- **Abbrechen** — nothing is sent

Verbatim JSON stays available on request (`show`); offer it, do not print it unprompted. Anything other
than an explicit confirmation means no push.

### 8. Push

```bash
bash "$PR/skills/feedback/scripts/sync.sh"              # "Alle pushen"
bash "$PR/skills/feedback/scripts/sync.sh" --only 1,3   # "Auswählen"
```

`--only` takes the numbers from the step-7 table. Unselected findings **stay pending** — they are not
marked synced, so a later run can still push them.

`sync.sh` pushes **finding records only** (raw event counts are local telemetry — the review flow
distills them into findings first; sync refuses with a hint if only counts are pending). It re-runs
`redact-check.js` as a hard gate on the exact payload (defense-in-depth), adds `pluginVersion` +
`reporter` (OS username), then POSTs ONE batch to the ingest webhook (`N8N_AUTOPILOT_FEEDBACK_URL`
overrides the default). The ingest workflow creates one issue per finding. On HTTP 200 sync moves all
pending records to `synced.ndjson` and lists the created issue URLs. If it exits non-zero, surface
the error verbatim and stop — nothing was pushed, nothing was marked.

---

## Interview (manual Q&A only)

Ask the user (accept "skip" per item):
1. Non-HTTP-Trigger-Test umständlich? 2. Konflikt-Auflösung häufig? 3. Validate→Fix-Schleifen / Fehler klar?
4. MCP-Publish genervt? 5. Node-Schemas gefehlt? 6. Rating 1–5. 7. Freitext (optional).

Store the raw Q&A as a `process` record, then **distill each concrete pain point into a typed
`finding` record** (step 5 schema) — only findings become issues:

```bash
node "$PR/skills/feedback/scripts/record.js" '{"answers":{...},"freeText":"..."}'
node "$PR/skills/feedback/scripts/record.js" '{"kind":"finding","type":"...","title":"...","observed":"...", ...}'
```

Then run the PII gate (step 6) before any sync.

---

## Show pending

```bash
node -e '
const fs=require("fs"),p=require("path");
const store=p.join(process.cwd(),".n8n-autopilot","feedback");
for(const f of ["events.ndjson","process.ndjson"]){const fp=p.join(store,f);if(!fs.existsSync(fp))continue;
for(const l of fs.readFileSync(fp,"utf8").split("\n")){const t=l.trim();if(!t)continue;
try{const r=JSON.parse(t);if(r.synced!==true)console.log(r.kind,r.ts,r.repoLabel,JSON.stringify(r.signals||r.insights||r.answers||{}));}catch(e){}}}
'
```

---

## Sync only

Runs the PII gate then pushes (see step 8). Always shows records + requires confirmation first.

> The `sync.sh` script is the ONLY place a push happens (one `curl` POST to the ingest webhook — no
> `gh`/GitHub account needed on the consumer side). No hook ever pushes — capture is local-only;
> the push is always this user-triggered, PII-gated, confirmed flow. Maintainer-side refinement of
> the rollup issue = the `feedback-triage` agent (that one DOES need `gh`).
