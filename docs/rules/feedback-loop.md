# Feedback Loop — capture + central feedback

`scripts/capture-feedback.sh` silently appends NON-PII friction signal counts (an anchored signal
taxonomy) from each session to `.n8n-autopilot/feedback/events.ndjson` in the consumer repo
(gitignored). A `SessionStart` probe (`scripts/check-feedback-pending.sh`) emits an `INFO:` nudge when
unsynced records exist.

**It runs on three events, not just `SessionEnd`** (since 5.3.0): `SessionEnd`, `PreCompact`, and
`SessionStart` with `source: resume`/`compact` — the record's `endReason` says which one fired
(`clear` / `precompact:auto` / `start:resume`). Reason: `SessionEnd` only fires on a *clean* end, so
long sessions that get resumed or left open captured **nothing at all** — measured gap 2026-07-01 to
07-27 with zero events despite multi-hour n8nac sessions. `source: startup`/`clear` is skipped (no
prior transcript to scan). Writes are deduped last-write-wins per `sessionId`, so multiple fires in one
session collapse into the newest (superset) count.

- **The actionable unit is a typed `finding` record — one finding = one GitHub issue.** Schema:
  `type` (schema-gap | cli-friction | validation-loop | mcp-detour | credential-gap | doc-gap |
  design-antipattern | bug | other), `severity`, `area` (node type / n8nac command), `title`,
  `observed`, `expected`, `suggestion`, plus `signals` evidence counts. Raw event counts alone are
  NOT pushable — the review flow distills them into findings first (sync refuses otherwise).
- `/n8n-autopilot:feedback` (default = **review**) — one-shot: reviews the session (auto-captured
  signals + file-level design metrics + a qualitative transcript pass), writes one finding per
  concrete problem, runs the deterministic PII gate, shows the result, then pushes.
- `/n8n-autopilot:feedback interview` — manual Q&A, then distilled into findings. `… show` — list
  pending. `… sync` — push only.
- **Push** = ONE `curl` POST to the plugin's ingest webhook
  (`https://n8n.neurawork.app/webhook/autopilot-feedback`, override via `N8N_AUTOPILOT_FEEDBACK_URL`).
  One path, no fallback, no `gh`/GitHub account needed on the consumer side. **Side-effecting +
  consent-gated**: shows every record, requires explicit confirmation.
- **Server side:** the n8n ingest workflow (`[Webhook] Ingest Feedback - GitHub Rollup`,
  id `2IzVbRZKbnnfBSpe` on the maintainer's instance) validates the envelope and creates **one
  `feedback`-labelled issue per finding** on the PUBLIC `neurawork-git/n8n-autopilot`. The issue
  carries reporter (OS username — by design), plugin version, severity, area, observed/expected/
  suggestion, signal evidence, and the raw finding JSON. The GitHub token lives only in the
  instance's credentials.
- **Refinement:** the `feedback-triage` agent (maintainer-side, needs `gh`) dedups the open feedback
  issues (closes duplicates with cross-reference), adds triage comments, and reports a ranked
  backlog. Re-runnable any time.
- **PII (defense-in-depth):** auto-capture stores only counts + repo basename. Because the target is
  public, `repoLabel` (a customer basename) is stripped from the payload before push, and
  `scripts/redact-check.js` deterministically BLOCKS unknown keys + free-text matching
  email/path/URL/long-digit/token/customer-name patterns — on top of the LLM redaction. Node types
  and n8nac command names are explicitly safe (and wanted, in `area`). No hook ever pushes; capture
  is local-only.
