---
name: feedback
description: Review the current n8n-autopilot session for learnings (operational friction + workflow design anti-patterns), strip all PII, and push the redacted insights centrally to the public plugin repo as a GitHub issue. Side-effecting on `sync`/`review`-push — shows the redacted result and requires explicit confirmation.
argument-hint: "[review | interview | show | sync]"
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash(bash:*), Bash(node:*), Bash(gh:*)
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

### 1. Resolve the session transcript

```bash
node "$CLAUDE_PLUGIN_ROOT/skills/feedback/scripts/latest-transcript.js" --workspace .
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

### 5. Compose the REDACTED insight record

Write neutral, reusable learnings. **No customer names, no file paths, no workflow content, no
values, no URLs.** Phrase findings as patterns ("Code node iterating a large DB result set → OOM
risk; recommend SplitInBatches"), not incidents ("<customer> workflow X crashed").

```bash
node "$CLAUDE_PLUGIN_ROOT/skills/feedback/scripts/record.js" '{"kind":"insight","signals":{"code_nodes":N,"native_conditional":N,"missing_descriptions":N,"overlapping_nodes":N},"insights":{"top_friction":"...","design":"...","suggestion":"..."}}'
```

### 6. Run the deterministic PII gate (show the user)

```bash
node "$CLAUDE_PLUGIN_ROOT/skills/feedback/scripts/redact-check.js" .n8n-autopilot/feedback/process.ndjson
```

- **OK** → proceed.
- **BLOCKED** → the gate lists the offending field. Re-redact that field (neutralize it) and rewrite
  the record, then re-run. NEVER bypass the gate.

### 7. Show every pending record + confirm

Display all pending records verbatim (run `show`). State the target
(`neurawork-git/n8n-autopilot`, a public GitHub issue — `repoLabel`/customer name stripped). Require an explicit **"ja / bestätigt"**.

### 8. Push

```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/feedback/scripts/sync.sh"
```

`sync.sh` re-runs `redact-check.js` as a hard gate before creating the issue (defense-in-depth), then
moves pushed records to `synced.ndjson`. Report the issue URL. If it exits non-zero, surface the
error verbatim and stop — nothing was pushed.

---

## Interview (manual Q&A only)

Ask the user (accept "skip" per item), then write a `process` record:
1. Non-HTTP-Trigger-Test umständlich? 2. Konflikt-Auflösung häufig? 3. Validate→Fix-Schleifen / Fehler klar?
4. MCP-Publish genervt? 5. Node-Schemas gefehlt? 6. Rating 1–5. 7. Freitext (optional).

```bash
node "$CLAUDE_PLUGIN_ROOT/skills/feedback/scripts/record.js" '{"answers":{...},"freeText":"..."}'
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

> The `sync.sh` script is the ONLY place `gh` runs. No hook ever pushes — capture is local-only;
> the push is always this user-triggered, PII-gated, confirmed flow.
