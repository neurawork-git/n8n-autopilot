# Feedback Loop — capture + central feedback

A `SessionEnd` hook (`scripts/capture-feedback.sh`) silently appends NON-PII friction signal counts
(an anchored signal taxonomy) from each session to `.n8n-autopilot/feedback/events.ndjson` in the
consumer repo (gitignored). A `SessionStart` probe (`scripts/check-feedback-pending.sh`) emits an
`INFO:` nudge when unsynced records exist.

- `/n8n-autopilot:feedback` (default = **review**) — one-shot: reviews the session (auto-captured
  signals + file-level design metrics from `workflows/*.workflow.ts` + a qualitative pass),
  LLM-redacts to neutral insights, runs the deterministic PII gate, shows the result, then pushes.
- `/n8n-autopilot:feedback interview` — manual Q&A only. `… show` — list pending. `… sync` — push only.
- **Push** = ONE labelled GitHub issue on the PUBLIC `neurawork-git/n8n-autopilot` via `gh issue create`
  (one path, no fallback). **Side-effecting + consent-gated**: shows every record, requires explicit
  confirmation. Because the target is public, `repoLabel` (a customer basename) is stripped from the
  issue title, summary, and raw NDJSON before push. Live web-server ingestion = future TODO.
- **PII (defense-in-depth):** auto-capture stores only counts + repo basename. Before ANY push,
  `scripts/redact-check.js` deterministically BLOCKS unknown keys + free-text matching
  email/path/URL/long-digit/token/customer-name patterns — on top of the LLM redaction. No hook ever
  pushes; capture is local-only.
