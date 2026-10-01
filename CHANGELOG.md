# Changelog

All notable changes to **n8n-autopilot** are documented here. Versions follow [Semantic Versioning](https://semver.org/).

## [5.6.0] — 2026-09-30

The reliability release. Triggered by a full pass over 68 open feedback issues, the synced friction
records and every customer-repo session of the last 120 days — which showed that the gates this
plugin is built around had never fired outside the plugin's own repo.

### Fixed
- **The PreToolUse gates were dead in real use.** Every gate read `$CLAUDE_TOOL_INPUT`; Claude Code
  delivers hook input as JSON on stdin and sets no such variable, so `INPUT` was empty and every
  gate exited 0. Measured: dozens of `npx n8nac push` calls, direct `curl` against `/api/v1` and
  un-pinned sessions across the customer repos — not one `[push-gate]`, `[enforce-env]` or
  `[push-lint]` line in 120 days of tool results. One dispatcher now (`scripts/pretooluse-gate.sh`,
  `matcher: Bash|PowerShell`) reads stdin, extracts `tool_input.command` and runs curl-block →
  enforce-env → push-gate → push-lint → mcp-trigger guard. The PowerShell tool, previously unmatched
  entirely, is gated the same way. `bash scripts/test-pretooluse-gate.sh` feeds both tools real
  stdin JSON (13 cases).
- **Greenfield author no-op halted stack resumes at 0/n (#58, #87).** `build.workflow.js` now
  continues into validate/deploy when the author reports `noChangeNeeded` with an existing file,
  as the edit flow already did. Gate test 10.
- **Reviewer skills were dead references.** `workflow-reviewer` listed `n8n-validation-expert` and
  `n8n-workflow-patterns`, which exist in no installed plugin; it now loads `n8n-architect`,
  `n8n-orchestration-patterns`, `n8n-code-javascript`.
- **Tester still described the 5.3 activate → production-URL test path**, contradicting the 5.4
  pinned MCP path (#37). Activation is now only the explicit final step of a build / stack.
- `init-repo` prescribed `env use`, which its own env-gate blocks (#49); it now pins
  `N8NAC_ENVIRONMENT` in `.claude/settings.json`. Its `.gitignore` template ignored that same
  settings file, leaving fresh clones with the plugin silently disabled (#54) — only
  `settings.local.json` is ignored now. It checks for an existing same-name GitHub remote before
  scaffolding (#53), and its reference n8nac version reads 2.7.0 (was 2.3.6).
- `feedback` skill: `$CLAUDE_PLUGIN_ROOT` is empty in the Bash tool, so every documented script call
  failed with MODULE_NOT_FOUND (#74, #100). The skill resolves the plugin root once into `$PR`.
- `check-installed-nodes.sh` accepts `N8N_HOST` / `N8N_BASE_URL` / `N8N_URL` as the base-URL name
  (#29); `setup-check.sh` honours `NODE_TLS_REJECT_UNAUTHORIZED=0` like n8nac (#52).
- Cheat-sheet `oAuth2Api` recipe no longer ships `allowedHttpRequestDomains`, which n8n ≥ 2.20
  rejects (#89); it says to run `credential schema` first.

### Added
- **Push-Lint stage 1b — version-gated parameters** (`scripts/param-version-check.py`). n8n gates
  parameters per `typeVersion` via `displayOptions['@version']`; `n8nac skills validate` checks the
  key's name, not the gate (#94, #84, #82, #60). The check reads the gated schema through n8nac's
  own `NodeSchemaProvider` for all types in one process (`scripts/node-schemas.mjs`, ~2 s cold,
  cached 24 h per type) and blocks a top-level key that exists only in other versions, naming the
  versions that have it. `--selftest` included.
- **Error-handling lint** (`lint-workflow.py`): `no-error-strategy` blocks a top-level workflow with
  external calls that has neither `settings.errorWorkflow` nor a wired error output;
  `masked-error` now requires the node's main output to feed an If/Switch/Filter/Code that tests
  `$json.error` (a `notes` justification no longer exempts — `executeWorkflow`/Postgres with
  `continueRegularOutput` reported success for failed steps); `retry-missing` warns on
  `httpRequest` without `retryOnFail` (#88); `code-env-access` warns on `$env` / `require()` in Code
  nodes (#97). Calibrated on the 79 local workflows of a real instance (numbers under *Known gaps* below).
- **Lint block = fix loop in the pipelines.** `build.workflow.js` and `edit.workflow.js` treat a
  `[push-lint] BLOCKED` from the deployer as a defect list: author fixes exactly the BLOCK lines,
  validator re-checks, deployer pushes again (max 3, `stage: 'lint'`). Drift / env blocks still
  fail at deploy, now with `blockedBy`. `n8n-deployer` returns hook output verbatim and backs off
  15/45/90 s on 5xx (#88). Gate tests 8 + 9.
- **Error strategy flows from research to author.** `n8n-researcher` reports the instance's
  errorTrigger workflow as `errorWorkflowId`; the author prompt tells the author to set
  `settings.errorWorkflow` to it, or to wire error outputs when the instance has none.
- **SessionStart probes run only in n8n repos** (`scripts/lib/n8n-repo-guard.sh`, #77): pinned env,
  a `*.workflow.ts`, `.n8n-autopilot/`, n8nac config, or a CLAUDE.md that mentions the plugin.
- `check-native-mcp.mjs` reports `WARN:` (was `INFO:`) when the pinned env has no native MCP —
  that state blocks every push.
- Reviewer checklist 16–20: useful error branches / idempotent retries, explicit `$('Node')`
  references across gaps (#64), sentinels through an If before URL interpolation (#75), read-back
  after silent-success API writes (#96), Code-node runtime access (#97). Author rules and the
  `n8n-code-javascript` skill carry the same.

### Known gaps (carried)
- Native MCP token for the internal tester env answers 401 (rotated) — reconfigure before the next
  live gate run; until then stage 1 of the push-lint gate blocks every push there, by design.
- Existing workflows: of the 60 local ones that compile, 30 have no error strategy and 11 carry a
  `continueOnFail` without a downstream check. They block on their next push until fixed — that is
  the point, and `N8N_AUTOPILOT_SKIP_LINT=1` remains the user's override.
- `no-description` (#31) and `$json`-across-gaps (#64) stay reviewer checks: the compiled JSON
  carries no description field, and the data source of a `$json` read is not decidable statically.

## [5.5.0] — 2026-09-22

### Changed
- **`n8n-native` ships with the plugin.** A stdio MCP server (`scripts/n8n-native-proxy.mjs`,
  declared in `plugin.json`) forwards the instance's test and read tools — `prepare_test_pin_data`,
  `test_workflow`, `execute_workflow`, `get_execution`, `get_workflow_details`, `search_workflows`,
  `get_node_types`, `search_nodes` — to the instance of the PINNED session env. Endpoint and token
  come from n8nac's store (`native-mcp configure`), so a customer repo reaches its own instance and
  no token sits in Claude Code's config. Without `N8NAC_ENVIRONMENT` it refuses instead of guessing.
  Write tools are not exposed at all, so the 5.4.0 write-block hook is gone, and so is the manual
  `claude mcp add` user-scope registration (it pointed every repo at one instance).
- `instance-node-check.mjs` and the proxy share `scripts/lib/native-mcp.mjs` (env resolution with
  config walk-up, MCP HTTP client with 429 retry). The gate calls it with plain `node`.

### Added
- **Setup integration.** SessionStart probe `check-native-mcp.mjs --quiet` prints the exact remedy
  when the pinned env has no native MCP config (INFO only — the fix needs a token from the n8n UI).
  `/n8n-autopilot:init-repo` step 4b and `/n8n-autopilot:check-mcps` step 4b (`--live`: connects and
  checks the test tools exist).

## [5.4.1] — 2026-09-22

Wired and measured against the live internal instance. 5.4.0 rested on the n8n source; the running
instance differs in three places, all fixed here.

### Changed
- **Default test = pinned, no side effects.** The tester runs `prepare_test_pin_data` →
  `test_workflow` → `get_execution`: triggers, credentialed nodes and HTTP Request nodes run on pin
  data, logic nodes run for real. Works for every trigger type, so the `non-mcp` / `manual-required`
  branches are gone. Live `execute_workflow` (manual = pushed draft, real side effects) only when the
  caller passes `testData`. Tool name is `prepare_test_pin_data` (5.4.0 had
  `prepare_workflow_pin_data`). Gate test 5 now expects the pinned path, new test 7 the live path.
- **Push-Lint-Gate stage 1 checks node types itself.** The instance exposes no
  `validate_node_config`, so n8nac's level-2 push validation is a no-op (it warns and validates
  against its bundled catalogue). New `scripts/instance-node-check.mjs` asks the instance's
  `get_node_types` per type@version, using the env's endpoint + token from n8nac's own config API.
  Blocks core nodes whose version or type the instance lacks (hidden/deprecated nodes such as
  `spreadsheetFile` included); community nodes only warn, because the catalogue misses installed
  ones (PandaDoc answered "not found" while it ran the same day). Retries HTTP 429 twice.
  Over the 78 local workflows: 77 pass, one blocks on `spreadsheetFile`.

### Documented (docs/rules/testing.md)
- `native-mcp status` / `doctor` report "disabled" from a repo dir — pass `--cwd <dir of n8nac-config.json>`.
- The n8nac MCP broker sends `version` as a number; the instance rejects it (`-32602`).
- `--token-stdin` reads a pipe and waits silently without one — PowerShell and Bash recipes.

## [5.4.0] — 2026-09-22

### Changed
- **Tests run through the instance's own MCP server, not its URLs.** `build-workflow-v2` and
  `edit.workflow.js` call native n8n `execute_workflow` with `executionMode: "manual"` (the pushed
  draft) and poll `get_execution`. Schedule and manual triggers are tested headless for the first
  time (#10, #72). Nothing is activated to test, so the activate → self-inflicted drift → `fetch`
  dance is gone (#37). Form, chat and webhook inputs are typed instead of a raw POST (#59, #71, #91).
  `prepare_workflow_pin_data` covers nodes that need real remote ids. `n8n-tester` gets the MCP tools;
  a missing server or `availableInMCP: false` returns `mcp-unavailable` and FAILS the build with the
  setup hint — no silent fallback to `n8nac test`. Setup: `docs/rules/testing.md`.
- **typeVersion is judged by the instance at push.** Agents no longer pick or demand "the highest
  version n8nac knows" (reviewer #9, author, node-verifier). n8nac 2.7.0's push preflight calls the
  instance's `validate_node_config` at native MCP level 2; that is the authority (#85, #82, #62, #94).

### Added
- **Push-Lint-Gate** (`scripts/push-lint-gate.sh`, PreToolUse on `npx n8nac push`). Stage 1 refuses
  the push unless native MCP assist is level ≥ 2, reachable and exposes `validate_node_config` —
  otherwise n8nac silently validates against its bundled catalogue. Stage 2 runs
  `scripts/lint-workflow.py` on the `convert` output and blocks on: 0-node compile (#20),
  missing/dead trigger, orphan node (#93), `continueOnFail`/`continueRegularOutput` without a
  `notes` reason, `continueErrorOutput` with an unwired error output, unbalanced `=`-expressions
  (#92), empty Code node, `responseNode` webhook without respond node, `availableInMCP` not true.
  Warns on Code-node share > 50 % (#76), missing sticky, overlapping positions. Calibrated on 78
  real workflows; two false-positive classes fixed. `python scripts/lint-workflow.py --selftest`.
- **MCP write block** — PreToolUse hook refuses workflow and data-table write tools on the
  `n8n-native` server; it is registered for testing only.
- `scripts/test-pipeline-gates.mjs` cases 5 + 6: schedule trigger proven via MCP without
  activation; `mcp-unavailable` fails the build.

## [5.3.6] — 2026-09-15

### Changed
- **Reference n8nac bumped 2.5.0 → 2.7.0** (2.6.0 + 2.7.0 both shipped 2026-09-11). `reference.md`
  regenerated from the live `--help` tree; cheat-sheet gains the new surface: `push --draft` (2.6+
  `push` otherwise *releases* the running version — the old "push writes a draft" mental model is
  wrong for published workflows), `skills batch --calls-file … --compact` (several ontology lookups
  in one process) and `node-info --compact`. Transformer 2.0.1 now round-trips `continueOnFail`,
  `disabled`, `notes`, `notesInFlow`, several sub-nodes on one AI input, and unmodelled node
  properties — earlier `pull` silently dropped them.
- **Companion plugin `n8n-as-code` reference is 2.4.1** (was 2.3.2 at user scope; 2.4.1 pins its
  ontology to **n8n 2.38.7**). Measured against a customer instance on n8n **2.20.11**: the
  bundled knowledge is 18 minor versions ahead of the target, which is the root of the
  version-drift findings (#62, #82, #85, #94). No guard for it exists yet — see *Known gaps*.

### Added
- **Instance cache** (`scripts/build-instance-cache.sh` + `check-instance-cache.sh` SessionStart
  probe): `.n8n-autopilot/instance-brief.md` / `instance-cache.json` describe what actually runs
  on the pinned instance (active workflows, proven node types, credential names, custom nodes).
  Consumed by `n8n-researcher` (local prior art before the public template corpus),
  `n8n-node-verifier` (`provenOnInstance`), `n8n-author` (credential ids from `credentials[]`)
  and `n8n-stack-architect` (reuse existing workflows as callees). Refreshed by the build skills
  before dispatch; the probe only reports (`INFO:`) because a rebuild hits the instance twice.

### Known gaps (carried)
- The cache holds **no `typeVersion`** — `n8nac list --json` does not return it and `pull` drops
  it during Decorator-TS conversion — so "highest version n8nac knows" is still what the author
  picks and what the reviewer (point 9) demands, while the instance may reject it (#85).
- Native n8n MCP assist (n8nac 2.7.0) stays **read-only**: `execute_workflow` / `test_workflow`
  wrappers are documented upstream as future work, so non-HTTP testing still goes through
  `/n8n-autopilot:test-manual`.

## [5.3.5] — 2026-07-28

### Added
- **`build-stack-v2` states its target env before it builds anything (#14).** New phase-0 `Preflight`
  resolves the active env / project / host, logs it, and returns it as `envContext` in every report —
  and says so explicitly when `N8NAC_ENVIRONMENT` is unset, because the run would then follow the
  SHARED global active env that another session can change mid-run. `enforce-env.sh` already refuses
  un-pinned instance commands, but only once a build agent is running, where the abort reads as an
  opaque tool error instead of "wrong environment".
- **EXTEND refuses to rebuild a stack it could not find.** Zero sub-workflows out of comprehension now
  returns `status: 'needs-decision'` (`reason: 'empty-comprehension'`) instead of falling through. That
  fall-through was the actual damage path: on a wrong-project env the mirror holds different workflows,
  comprehension finds nothing, the delta planner marks **every** sub-WF `new`, and the pipeline rebuilds
  the whole stack against the wrong project — looking like normal progress the entire time. The skill
  doc spells out not to "fix" it by re-running as greenfield.

### Added (issue sweep)
- **`agents/n8n-author.md` — "Silent-failure traps"** table for four defects that pass `validate --strict`
  *and* report `success`, because the parameter exists but is inert (#17, #9, #15, #19): an `httpRequest`
  body dropped when `specifyBody`/`contentType` do not match it; array params given as `{}` (GitHub
  `labels` → `labels.map is not a function`, and silently discarded entirely without push access);
  `binaryPropertyName` without the `binaryData` flag writing a 0-byte file; fetch allowlists that never
  return fields added later.
- **`agents/n8n-tester.md` — "`status: success` is not proof"**. An execution succeeds when no node threw,
  which is weaker than "it did its job". The tester must read the output before certifying: zero-byte
  artifacts, unfiltered result sets, silently dropped fields, binary stubs — and check for a pending
  **draft** before treating unchanged behaviour as a wiring defect (#18, #15).
- **Estate Health in `/n8n-autopilot:inventory`** (#30, #31) — Code-vs-native branching ratio and the share
  of workflows documenting no intent. Both drifts are invisible per file and only exist in aggregate,
  which is why they accumulate; measured on the tester repo: ratio 0.90, and 71/78 files with no
  `description` anywhere.
- **`docs/troubleshooting/auth-and-scopes.md`** (#32, #8, #28, #6) — a `403` on one endpoint while the same
  key works everywhere else means the API key lacks that *scope*: n8n checks the key's own `scopes` column
  with **no** fallback to the user's global role, and never backfills scopes onto an existing key, so
  re-pasting it provably cannot help. `sync-credentials` and `find-credential` now detect the 403 and print
  this cause, the fix, and the UI route to a credential ID instead of a generic failure. Also: `env auth` is
  per **environment**, not per instance target; and the diagnostic path for an activation failure whose
  cause n8nac swallows.
- **`docs/rules/gates.md` — batch deploys** (#21): self-inflicted activation drift clears with `fetch`, a
  stale local needs the per-file `pull`, and a genuinely local-authoritative batch exports the bypass once
  around the loop. No "remote is an ancestor" auto-detection: n8nac reports a status word, not ancestry,
  and a wrong guess silently destroys a UI edit.

## [5.3.4] — 2026-07-28

### Fixed
- **`check-workspace-migration.sh` no longer tells you to delete a config n8nac is actively using.** It
  flagged any in-repo `n8nac-config.json` as stray and printed `rm <repo>/n8nac-config.json`. On 2.5.0 the
  CLI reads that file, and where no home config exists it is the *only* one — the advice destroyed every
  environment binding in the workspace. The probe now reads whether `~/n8nac-config.json` /
  `~/.n8n-manager/` exist and classifies four cases (live / conflicting / superseded / sole-but-old),
  suggests a reversible `mv` instead of `rm` even where deletion is safe, and stays **silent** in
  `--quiet` when the in-repo config is simply the live one. Same wrong instruction removed from
  `CLAUDE.md`, `docs/rules/setup.md`, `README.md`, `README.de.md`.
- **Partial feedback pushes no longer discard the records they did not send.** `sync.sh` marked *every*
  unsynced record as synced on success; with the new `--only` that would silently drop exactly the
  findings the user chose to withhold — invisibly, since the store is gitignored and nothing is re-sent.
  It now marks only what was actually pushed.
- Stale version claims corrected across the docs: n8nac reference `2.3.6` → **2.5.0** (matching the
  `REFERENCE_N8NAC_VERSION` SSOT) and the README version badge `4.10.0` → current, in both languages.
  The CRLF notes in the skills now say the corruption is *sporadic* (`sync.workflow.js` was CRLF in
  5.3.0/5.3.1, LF in 5.3.2) — the old wording implied it was deterministic, inviting people to skip the
  normalization once they saw an LF copy.

### Added
- **`scripts/check-custom-nodes-resolution.sh`** — SessionStart probe for the silent community-node
  trap. When `workflows/` reference community packages while n8nac has no custom-node source loaded,
  `skills search` / `node-info` return a confident **empty** result instead of erroring, and research
  concludes the node does not exist. The probe cross-references discovered community packages against
  `customNodesLoaded` (scraped from `skills list --nodes --debug`, which prints that block to **stderr**)
  and spells out both traps: an empty result for a listed package is a resolution failure, and
  `pull-schemas` does *not* fix it — it fills the plugin's own cache, a different mechanism. `INFO:` only,
  no auto-action: authoring `n8nac-custom-nodes.json` is not something the plugin can do for you.
- **`sync.sh --only 1,3`** plus a compact confirmation flow — the feedback skill now shows one line per
  finding and asks via `AskUserQuestion` (push all / select / cancel) instead of dumping records verbatim.
- **`scripts/test-feedback-sync.sh`** — 8 checks against a local HTTP stub (never the real webhook)
  covering partial push, full push, and an invalid selection, for both what is *sent* and what is *marked*.
- Author rule: workflow class identifiers must be plain ASCII (#20's greenfield half). Deliberately narrow
  — `name`, `description`, node names and sticky-note text keep their umlauts.

## [5.3.3] — 2026-07-28

### Fixed
- **SessionStart probes no longer mandate an auto-action that provably cannot succeed.** `AUTOPILOT_ACTION_REQUIRED`
  is a hard instruction — the assistant must run the named command without asking — so a probe that emits it for a
  condition the action cannot resolve burns a pipeline every session and teaches everyone to ignore the mechanism.
  Both offenders tested a different condition than their action repairs:
  - `check-credential-freshness.sh` flagged credential references by **ID**, while `--fix-workflows` joins on
    credential **name** inside the pinned project. Measured on the tester instance: 6 IDs reported stale, fixer
    output `No stale credential IDs found.` — all six are orphans (the name resolves nowhere), which no rewrite can
    repair. The probe now asks the fixer (`--dry-run`, new exit code 3 == "would rewrite") before emitting the
    signal, and otherwise reports the orphans as `INFO` with the manual fix.
  - `check-mirror-drift.sh` trusted `n8nac list`'s status field alone. It now checks whether the reported
    `filename` actually exists under `workflows/`, and only real absence counts as drift.
- **Corrects the 5.3.2 explanation of the non-converging mirror sync.** That entry blamed `pull` refreshing only
  NEW local state entries. Re-measured today: both stuck workflows have a **present** state entry with the correct
  `filename`, the file is on disk under exactly that name, the decorator carries the right id, and every one of the
  78 remote filenames exists locally — yet `list` still reports `EXIST_ONLY_REMOTELY`, and neither `pull` nor
  `fetch` clears it. Local validity is not the discriminator either (4 `TRACKED` workflows fail `validate`). It is
  an n8nac status artefact with no local remedy, so the probe now classifies it as such instead of demanding a sync.

### Added
- `scripts/test-probe-symmetry.sh` — regression test for the probe/action symmetry rule. Runs both probes in a temp
  workspace against a stubbed `npx` and a stubbed fixer; asserts the mandatory signal fires for a genuinely fixable
  condition and stays silent for a phantom or orphan one. Verified discriminating: 2 of its 6 checks fail against 5.3.2.

## [5.3.2] — 2026-07-27

### Fixed
- **A dropped structured-output call in `mirror-sync`'s Verify phase discarded a fully successful run.**
  Observed live: all 4 remote-only workflows pulled and landed on disk, then the verify agent finished
  without emitting its result — the script called it bare (no `safe()` wrapper, unlike the v2 pipelines),
  so the run aborted with `agent({schema}): subagent completed without calling StructuredOutput` and
  reported `failed`. The pulled file paths survived only in the journal. Discover + Verify now use the
  same retry-plus-fallback helper; an inconclusive verify returns `partial` **with** the pulled files and
  `remoteOnlyRemaining: null`.
- **`mirror-sync` now says when re-running cannot help.** `npx n8nac pull` refreshes a workflow's local
  state entry only when that entry is NEW: measured on four workflows — the two with fresh entries got
  today's `lastSyncedAt`, the two with stale February entries kept them despite a correct file on disk
  with the right decorator id, and a serial re-pull changed nothing. They keep reporting
  `EXIST_ONLY_REMOTELY`, so the SessionStart drift probe mandates this skill every session forever. The
  result now carries an explicit `attention` telling you to check the local file and stop looping.

## [5.3.1] — 2026-07-27

### Fixed
- **Every skill that invokes a `.workflow.js` now normalizes it into the scratchpad first**
  (`sed 's/\r$//'`) and passes that path — unconditionally, not as a fallback. Installed copies arrive
  with CRLF even though the repo blob is LF and `.gitattributes` pins `*.js text eol=lf`; measured with
  `file`: `mirror-sync/sync.workflow.js` CRLF in 5.1.0, 5.2.0 **and** 5.3.0, `build.workflow.js` CRLF in
  5.2.0 but LF in 5.3.0 (different inodes per version, so no cache reuse — the install path converts).
  `Workflow({scriptPath})` refuses such a file outright ("script contains control characters that would
  be hidden in the approval dialog"), which blocked `/n8n-autopilot:mirror-sync` on a fresh 5.3.0
  install. The normalized copy is byte-identical to the blob (`cmp` against `git show HEAD:<path>`).

## [5.3.0] — 2026-07-27

Pipeline triage + gate classification, from a session review where a stack EXTEND spent 83 subagents
and 67 minutes without moving the critical path. Full analysis: [docs/PRD-5.3-pipeline-triage.md](docs/PRD-5.3-pipeline-triage.md)
(issues #33–#40).

### Fixed
- **Class-B fix loop ignored its own author agent.** The fix call's return value was discarded, so a
  `written:false` verdict ("not a wiring bug — the test payload carries placeholder ids") was
  overridden and the same bytes were repushed and retested. Observed: 4 identical cycles, ~14 of 80
  subagent results. The loop now breaks on that verdict and reclassifies the run as `test-data-gap`.
- **A no-op edit is no longer a failure.** `edit.workflow.js` returns `{status:'success', noop:true}`
  when the requested change is already present (comprehend refreshed to remote base, so local ==
  remote) and skips validate/deploy/test. Previously each no-op returned `failed` and HALTed the whole
  stack — 4 of them in one run.
- **Self-inflicted drift.** The pipeline's own `workflow activate` changes the remote sync hash; the
  resulting `MODIFIED_BOTH` blocked both push and pull and left `resolve --mode keep-current` (the
  bypass the gate exists to prevent) as the only way out. Deployer now re-baselines with `fetch` for
  this case only; documented in [docs/rules/gates.md](docs/rules/gates.md).
- **Publish order is not a broken workflow.** n8n refuses to activate a caller whose callee is not
  published. `build-stack-v2` grew an `Activate` phase that walks the graph deps-first; sub-builds run
  with `deferActivation`/`deferTest`. The tester's "activation failure = broken workflow" rule now
  checks the callee-unpublished cause first.

- **Auto-capture never fired for long sessions.** `capture-feedback.sh` was wired to `SessionEnd`
  only, which fires on a *clean* end (`clear` / `prompt_input_exit`). Sessions that get resumed or
  left open — the ones with the most friction — produced nothing: measured gap 2026-07-01 to 07-27,
  zero events across multi-hour n8nac sessions, while the Stop-gate kept working. Now also on
  `PreCompact` and `SessionStart` (`source: resume`/`compact`), with the firing event recorded in
  `endReason`; `startup`/`clear` are skipped (no prior transcript). Dedup stays last-write-wins per
  session.
- **Every captured event was versionless.** `n8nacVersion` read `<cwd>/node_modules/n8nac/package.json`,
  which never exists under npx usage → `""` in all telemetry so far. It now falls back to the highest
  n8nac version found in the npx cache (no spawn).

### Added
- `outcome: 'test-data-gap'` in the test schema + classification rules in `n8n-tester` (external 4xx
  from synthetic input is not a wiring defect).
- `noChangeNeeded` in the author contract — "nothing to do" is a first-class, non-failing answer.
- `specPath` + `referenceStack` args for `build-stack-v2`, injected into architect/build/change
  prompts, so the fan-out mirrors a proven twin instead of re-deriving contracts.
- `status` vs **`proven`** split: `status:'success'` = build gates green, `proven:true` = a real
  execution was inspected. `non-http` / `test-data-gap` / `deferred` are green builds with
  `proven:false` — a stack is proven ONCE, end to end, not per sub-workflow with fake payloads.
- `scripts/test-pipeline-gates.mjs` — runnable gate regression check (stubs the Workflow runtime, no
  agents spawned). Fails against the pre-5.3.0 code.
- Cheat-sheet recipe for `oAuth2Api` + `clientCredentials`, including the `allowedHttpRequestDomains`
  enum trap (`"none"` breaks HTTP Request nodes at runtime) and the missing `credential update`.

### Changed
- `.gitattributes` also pins `*.mjs` to LF. The 5.3.0 install arrived as LF, but the cached 5.2.0
  copy is CRLF — the pin is not a guarantee across install paths, so both v2 skills now document the
  `file`-check plus the `sed 's/\r$//'`-into-scratchpad workaround for "script contains control
  characters", instead of leaving it to be rediscovered mid-run.
- Reference skill regenerated for **n8nac 2.5.0** (new: `env auth clear <name-or-id>`; `env auth`
  help wording clarified). `REFERENCE_N8NAC_VERSION` → 2.5.0, minimum unchanged at 2.3.0.

## [5.2.1] — 2026-07-14

### Fixed
- **Stop-hook feedback gate rendered as a red "Stop hook error".** The gate signalled its block via
  exit 2 + stderr, which the client displays as an error line. It now uses the JSON decision API
  (`{"decision":"block","reason":…}`, exit 0) — same behavior (the agent must propose
  `/n8n-autopilot:feedback review`), clean rendering.

## [5.2.0] — 2026-07-14

Feedback loop rebuilt end-to-end around actionable, typed findings, plus the n8nac 2.4 refresh.

### Added
- **Typed `finding` records — one finding = one GitHub issue.** A finding carries `type`
  (schema-gap | cli-friction | validation-loop | mcp-detour | credential-gap | doc-gap |
  design-antipattern | bug | other), `severity`, `area` (node type / n8nac command), `title`,
  `observed`, `expected`, `suggestion`, and `signals` evidence counts. Raw auto-captured signal
  counts are local telemetry only — `sync.sh` refuses to push until the review flow distills them
  into findings. Issues include the reporter (OS username) and the raw finding JSON.
- **Webhook ingest transport — no `gh` needed on the consumer side.** Push is ONE `curl` POST to the
  plugin's ingest webhook (override via `N8N_AUTOPILOT_FEEDBACK_URL`); the maintainer-side n8n
  ingest workflow owns the GitHub token and creates one labelled issue per finding.
- **`feedback-triage` agent (maintainer-side).** Dedups open `feedback` issues (closes duplicates
  with cross-reference), adds triage comments, reports a ranked backlog. Re-runnable.
- **`Stop` hook (`scripts/suggest-feedback.sh`).** After a work turn in a session with real n8nac
  activity and no recorded finding, it blocks the stop once and makes the agent actively propose
  `/n8n-autopilot:feedback review`. Fires once per session, never loops, silent otherwise.
- **`native-mcp` coverage (n8nac 2.4).** Cheat-sheet section, `docs/MCP.md` guide with a test-path
  evaluation (read-only assist today; binary payloads never via MCP), and full command reference.
- **Activation-failure hard rule.** A failing `n8nac workflow activate` means the WORKFLOW IS BROKEN
  (node issues — most often a service node without a `credentials:` block). The `n8n-tester` agent
  now diagnoses and classifies this as a fixable Class B error; asking the user to activate in the
  n8n UI is forbidden (CLAUDE.md NEVER list + build-workflow Path C).
- `.gitattributes` pinning LF for scripts — CRLF checkouts on Windows broke `Workflow({scriptPath})`
  ("script contains control characters").

### Changed
- `sync.sh` dedups event records per `sessionId` (cumulative counters — last wins), fills
  `pluginVersion`, and reports the created issue URLs.
- `redact-check.js` allowlists the finding fields, enforces the type/severity taxonomy, and scans
  the new free-text fields; node types and n8nac command names are explicitly safe context.
- Reference skill regenerated for **n8nac 2.4.0** (adds the `native-mcp` command group);
  `dump-n8nac-help.sh` allowlist extended accordingly; stale "MCP entry-point broken upstream" note
  in build-workflow corrected.

## [5.1.0] — 2026-06-29

Hardening pass from a multi-session friction analysis of real production runs: documented gotchas
that were never enforced, and a noisy feedback metric.

### Added
- **build-workflow-v2 design-quality gate.** `workflow-reviewer` now runs as a hard gate between
  Validate and Deploy (≤2 fix cycles) in both greenfield + edit flows. Design anti-patterns the n8n
  validator cannot catch — raw HTTP in Code nodes, `continueOnFail`/`onError` masking real errors, AI
  sub-nodes miswired via `.out().to()` — now block the push instead of shipping. Warnings are
  surfaced (`reviewWarnings`) without blocking.
- **Orchestrator StructuredOutput resilience.** Schema'd subagent calls in build-workflow-v2 +
  build-stack-v2 now route through a `safe()` wrapper: a subagent that ends without calling
  StructuredOutput (or dies terminally) gets one retry, then a graceful fallback into the existing
  gate-failure path — instead of crashing the whole run with an opaque error after burning the
  tokens (observed: a heavy agent burned ~786k tokens, then the workflow aborted opaquely).
- **build-stack-v2 greenfield auto-detect.** Before decomposing, a greenfield stack build checks
  `docs/*.architecture.md` for a stack that already covers the use-case and returns
  `needs-decision` (re-run as extend, or pass `mode: 'greenfield'` to force) instead of silently
  rebuilding a working stack from scratch.
- **Feedback sync → public repo.** Target moved from the private `n8n-autopilot-internal` to the
  public `neurawork-git/n8n-autopilot`. `repoLabel` (a customer basename = PII on a public repo) is
  stripped from the issue title, summary, and raw NDJSON before push; records keep it locally.
- **SessionStart plugin-staleness probe** (`check-plugin-version.sh`) — INFO nudge to
  `claude plugin update` when the installed version is behind the latest GitHub release. Never
  auto-runs (env-changing). Catches the case where a stale install silently lacks newer gotcha hooks.
- **Cheat-sheet rows**: credential-schema-first (`n8nac credential schema <type>` before create) and
  sub-workflow-publish-before-parent.

### Fixed
- **Wrong execution-list flag** in the cheat-sheet/reference: `--workflow` → `--workflow-id` (n8nac
  rejects `--workflow`; the documented form caused the same CLI error across sessions). 5 files.
- **REST-guard dodge.** The PreToolUse curl-block only matched `curl`/`wget`, so `urllib` /
  `Invoke-RestMethod` / `requests.` slipped past it. Guard now catches those against `/api/v1` too;
  the `/api/v1/data-tables` carve-out is preserved, and the skill blesses looping its `curl` for
  polling (instead of reading n8nac's internal secret store).
- **env-blind `workspace status` trap.** CLAUDE.md recommended `workspace status` to verify the env,
  but it reports the GLOBAL active env — this misled the model into the forbidden `env use` across 3
  sessions. Docs now route env verification to `env list --json`.
- **Noisy feedback metric.** `capture-feedback.sh` matched skill-listing + SessionStart-hook
  injections (false positives) and double-counted on resume. Now scans only real conversation turns
  and keeps one last-write-wins event per session.

## [5.0.0] — 2026-06-08

### ⚠ BREAKING — minimum n8nac raised 2.2.0 → 2.3.0

The plugin now requires **n8nac ≥ 2.3.0**. n8nac 2.3 removed the `workspace pin-instance` /
`set-project` / `set-sync-folder` / `migrate*` mutators and the `instance-target` command, replacing
them with the environment-centric `env` model that the plugin's setup, init-repo, and credential flows
now depend on. Setups pinned to n8nac < 2.3 will fail the SessionStart `setup-check` (hard error) and
the init/credential flows will break. Since n8nac is run via `npx` (always latest), most users upgrade
transparently; anyone pinning an older n8nac must move to ≥ 2.3.0.

### Changed — n8nac compatibility bump 2.2.1 → 2.3.6 (environment-centric config model)

n8nac 2.3.x replaced the workspace-mutation config model with an **environment-centric** model.
`n8nac workspace` is now read-only (`status` / alias `get` only); all instance-binding, project, and
sync-folder config moved onto `env`. Native cross-env `promote` was added in 2.3.0.

**Removed commands** (no longer exist — do not use):
- `n8nac workspace pin-instance` / `clear-instance`
- `n8nac workspace set-project` / `clear-project`
- `n8nac workspace set-sync-folder` / `clear-sync-folder`
- `n8nac workspace migrate` / `migrate-v1`
- `n8nac instance-target` (entire command + subcommands add/list/remove/update)

**New / replacement commands:**
- `n8nac env add <name> --base-url <url> --workflows-path workflows` — create + bind an environment
- `printf '%s' "$N8N_API_KEY" | n8nac env auth set <name> --api-key-stdin` — store API key
- `n8nac env use <name>` — activate (alias of `env pin`)
- `n8nac env update <name> --project-name <P>` — replaces `workspace set-project`
- `n8nac promote [path] --from <env> --to <env>` — native cross-env promotion

**Plugin-side updates:**
- `REFERENCE_N8NAC_VERSION` bumped 2.2.1 → 2.3.6; minimum version bumped 2.2.0 → 2.3.0 in
  `scripts/setup-check.sh`
- `scripts/dump-n8nac-help.sh` — dropped the dead `instance-target` node;
  `skills/n8nac-reference/reference.md` regenerated against 2.3.6
- `scripts/setup/`, `skills/init-repo/`, `README.md`, `CLAUDE.md`, `skills/n8nac-cheatsheet/` —
  all setup and mutation references migrated from `workspace pin-instance` / `set-project` /
  `set-sync-folder` to `env add` / `env auth set` / `env update` / `env use`
- `skills/find-credential/`, `skills/find-project/` — workspace-mutation calls removed
- `scripts/check-workspace-migration.sh` — neutered; the migrate commands no longer exist, so
  stale `./n8nac-config.json` detection now instructs the user to **delete the file manually**
  (config lives in `~/n8nac-config.json` + `~/.n8n-manager/`; no migrate command available)

**Kept unchanged:** `n8nac workspace status --json` (read-only effective-context resolver, still
valid), `n8nac setup --mode <mode>` facade (still exists; binding now follows via env commands),
per-session `N8NAC_ENVIRONMENT` pin model and the `enforce-env.sh` / `report-session-env.sh` hooks.

### Added — session-env isolation: clobber-guard + `session-env` skill + isolation test

Closes the one hole in the per-session env model: `env use` / `env pin` mutate the machine-GLOBAL
active env (shared across all shells and Claude sessions), so a session running it silently re-points
every other un-pinned session. Empirically reproduced (15/17 → the two clobber-guard assertions failed
before the fix), then closed.

- **`scripts/enforce-env.sh` clobber-guard** — `env use` / `env pin` are now **blocked
  unconditionally** (exit 2), with a clear message steering to `N8NAC_ENVIRONMENT`. Deliberate
  machine-default changes bypass via `N8N_AUTOPILOT_ALLOW_ENV_USE=1`. Read-only `env list` / `env
  status` stay allowed.
- **`scripts/test-env-isolation.sh`** — empirical proof harness (17 assertions, read-only against
  instances, never runs `env use`): routing via `N8NAC_ENVIRONMENT` + `--env` to distinct hosts,
  the **safety invariant** (global active untouched by session pins, re-asserted at end), `workspace
  status` env-blindness, and full gate + clobber-guard behaviour. Verified `=== 17 passed, 0 failed ===`.
- **`skills/session-env/`** (`/n8n-autopilot:session-env`) — documents the model (global active vs
  per-session `N8NAC_ENVIRONMENT`), the three resolution scopes, both enforcement hooks, the
  `workspace status` gotcha, and runs the verification/test. Linked from the CLAUDE.md Env-Gate
  section + cheat-sheet.
- **Env-blind call-site fixes** — three skills used `workspace status` (env-blind) as a SESSION
  project resolver and so scoped to the wrong project when the session was pinned elsewhere:
  `find-credential/search.js`, `find-project/list.js`, and `sync-credentials/fix-workflows.js` (the
  last writes credential IDs into workflow files → real corruption risk). All three now resolve the
  active project from `env status --json` (session-aware). `workspace status` is deliberately kept
  for global-binding/liveness checks (`setup-check.sh`, `check-installed-nodes.sh`) — not forbidden.
- **Workflow env-propagation verified** — empirically confirmed (probe Workflow, generic agent +
  the real `n8n-tester` agentType) that `N8NAC_ENVIRONMENT` propagates session → Claude Workflow
  runtime → `agent()` subagent Bash, so the v2/stack pipelines' "env is inherited, run bare" design
  routes to the correct instance. Both agents resolved the session env + host; bare instance commands
  ran against the right env and left the global active untouched.

## [4.9.0] — 2026-05-30

### Added — build-stack-v2 (workflow-stack orchestrator) + stack-intake interview

Lifts the deterministic v2 discipline from a single workflow to a whole **stack** (an orchestrator plus
the sub-workflows it calls via Execute Workflow nodes).

- **`build-stack-v2`** skill (`skills/build-stack-v2/stack.workflow.js`) — JS-orchestrated, two modes:
  - **GREENFIELD** — Plan (decompose a PRP into sub-WFs + handover contracts) → Document
    (`docs/<stack>.architecture.md` with a deterministically-composed mermaid graph + contract tables)
    → Build (**topological bottom-up**, one `build.workflow.js` hop per sub-WF, each child's real
    `workflowId` fed into its parent's Execute Workflow node) → Report.
  - **EXTEND** — Mirror (`mirror-sync`) → Comprehend (reconstruct the call-graph from `executeWorkflow`
    refs in the local mirror) → Delta-plan → Apply (new sub-WFs bottom-up via `build.workflow.js`, then
    changed sub-WFs / orchestrator rewiring via `edit.workflow.js`) → Report.
  - A failed child build **halts** its dependents (no building on a broken foundation) and escalates;
    `status:'success'` only when every planned sub-WF built green. Reuses build-workflow-v2's scripts
    verbatim via the `workflow()` hook (1-level nesting), so every sub-WF gets the same hard gates.
- **2 agentType definitions** — `n8n-stack-architect` (decompose + delta-plan; `skills:`
  n8n-orchestration-patterns / n8n-structured-extraction / n8nac-cheatsheet / n8n-architect) and
  `n8n-stack-comprehender` (reconstruct the DAG from code, reconcile/regenerate the architecture doc).
  Both read-only.
- **`stack-intake`** skill — a guided, classic interview for users **not yet experienced with n8n**:
  asks about overall inputs, outputs, a concrete worked example, expected behavior, external systems,
  volume, and failure handling, then synthesizes a PRP-style use-case file
  (`docs/stack-prps/<slug>.prp.md`) ready for `build-stack-v2`. Plans only — never touches the instance.

### Note

- **Experimental + test-gated.** End-to-end stack runs should only be trusted once `build-workflow-v2`
  (greenfield + edit) is green against the target instance and the `skills:` pass-through is verified.
  The scaffold ships now; the live stack test follows that gate.

## [4.8.1] — 2026-05-29

### Added — plugin-testing skill + session-state capture

- **`skills/plugin-testing`** — the canonical (and only supported) way to test plugin changes: commit →
  push to the private repo → install FROM that GitHub repo → restart → verify registration. Documents
  the hard anti-patterns (no cache hand-copying, no directory-pointer marketplace, no hand-edited
  `settings.json`, `/reload-plugins` insufficient for new agents) and a verification probe.

## [4.8.0] — 2026-05-29

### Added — JS-orchestrated workflow pipeline v2 (experimental) + env-awareness

**Deterministic gates via Claude Code Workflow scripts.** Where `build-workflow` (v1) is prose the
model is *asked* to follow, v2 encodes the gate sequence as JS control flow the model cannot skip,
reorder, or short-circuit (validate before push; test only after `push --verify`; `status:success`
only after the execution is inspected; bounded fix-loops as real `while` counters).

- **`build-workflow-v2`** skill — two modes: GREENFIELD (`build.workflow.js`) and EDIT
  (`edit.workflow.js`, local-first: refresh to remote base → patch → drift-safe push). Subagent roles
  are extracted into namespaced agentTypes (`agents/n8n-*.md`), resolved in-workflow as
  `n8n-autopilot:n8n-*` (proven: Workflow resolves+spawns namespaced plugin agents).
- **`mirror-sync`** skill (`sync.workflow.js`) — pulls every remote-only workflow so the repo mirrors
  the instance (discover `/REMOTE/i` status → fan-out `pull` → verify). Establishes the local-first
  invariant the edit flow relies on. Auto-triggered by the SessionStart drift probe.
- **8 agentType definitions** — `n8n-researcher`, `n8n-node-verifier` (adversarial param contract),
  `n8n-comprehender`, `n8n-author`, `n8n-validator`, `n8n-deployer` (drift-aware), `n8n-tester`,
  `n8n-mirror`. Reusable across v1/v2 and via the Agent tool directly.

### Added — n8n environment safety (one env per session)

- **`scripts/enforce-env.sh`** (PreToolUse hard gate) — blocks any instance-touching `npx n8nac`
  command that resolves to NO explicit env (no `--env`, no inline/session `N8NAC_ENVIRONMENT`),
  preventing silent operations against the shared GLOBAL active env. Local/config subcommands
  (skills/convert/workspace/env/setup/…) are never gated. Fail-closed.
- **`scripts/report-session-env.sh`** (SessionStart) — states the session's env (instance + project)
  up front; warns when none is pinned and only the shared global-active env would be used.
- Model: **one env per Claude session** via `N8NAC_ENVIRONMENT` (per-repo default in
  `.claude/settings.json` `env` block). **Workflow subagents inherit it** (verified empirically) — so
  agents run `npx n8nac` BARE and hit the right (instance + project); prompt-injected `--env` flags were
  tried and dropped unreliably, so agent defs now FORBID `--env`/`env list`/env-probing. Different
  sessions target different projects simultaneously — never a global `env use` switch. An n8nac env =
  (instance host + n8n project). `setup-check`/`report-session-env` resolve via `env status` (honors
  `N8NAC_ENVIRONMENT`), not `workspace status` (which only sees the global active env).
- Fan-out reliability: a **retry-once pass** catches subagents that finish without emitting their
  StructuredOutput result (idempotent ops like `pull` re-run safely) — prevents false under-reporting.
- **`scripts/check-mirror-drift.sh`** (SessionStart) — emits `AUTOPILOT_ACTION_REQUIRED:
  /n8n-autopilot:mirror-sync` only when remote-only workflows exist (no blind every-session pull).
- `init-repo` step 6.5 runs `mirror-sync` after schema pull so a fresh repo starts as a full mirror.

## [4.7.0] — 2026-05-29

### Added — idempotent CLAUDE.md section anchoring for existing repos

`init-repo` previously only wrote a templated `CLAUDE.md` for brand-new repos; an existing repo with
its own `CLAUDE.md` was skipped, so the autopilot guidance never landed there.

- New `skills/init-repo/scripts/ensure-claude-section.js` — idempotently anchors a marker-delimited
  n8n-autopilot section (`<!-- n8n-autopilot:start -->`…`<!-- n8n-autopilot:end -->`) into `CLAUDE.md`:
  creates the file if missing, refreshes the block in place if markers exist (no duplication),
  appends to a foreign CLAUDE.md, and SKIPs a full-template CLAUDE.md (sentinel) unless `--force`.
  Content outside the markers is never touched.
- New section template `skills/init-repo/assets/templates/CLAUDE-section.md` — entry points,
  SessionStart auto-reactions, design-quality rules, pattern-skill pointers, NEVER rules.
- `init-repo.sh` runs it after scaffolding (non-fatal on failure). Also runnable standalone on any
  existing repo: `node …/ensure-claude-section.js --workspace .`.

## [4.6.0] — 2026-05-29

### Added — workflow-pattern guidance skills (org-learned, concrete examples)

Distilled from real production memories + debates into reusable, example-driven guidance.

- **`n8n-orchestration-patterns`** (new auto-activated skill) — fan-out / fan-in and parallel
  sub-workflow execution. Covers the branch-split trap (`executionOrder: v1` runs serially), Pattern A
  (`executionOrder: v0` layer interleaving), **Pattern B = Wait-OFF + DataTable fan-in (recommended)**,
  Pattern B2 (resumeUrl, veto grey-zone), Pattern C (queue mode), synchronous-batch + fast-return
  webhook, and the error-output-not-`continueOnFail` rule. With TS config examples.
- **`n8n-structured-extraction`** (new auto-activated skill) — LLM extraction/classification via a
  real JSON schema using `informationExtractor` / `textClassifier`, never an AI-Agent "return JSON"
  prompt. Documents the reasoning-model failure modes (`{"output":...}` wrap, enum/umlaut violations)
  and a full Information-Extractor schema example (typed + described fields, ASCII-safe enums).
- **`data-tables`** extended — the workflow-node **upsert shape** (3-part requirement:
  `filters.conditions` keyName+condition+keyValue **and** `matchingColumns`) + usage patterns
  (fan-in store, idempotency/dedup via upsert, error rows, cross-run state, count-race safety).

## [4.5.0] — 2026-05-29

### Added — Design-quality learnings + `/feedback` session-review-redact-push flow

A second analysis dimension — workflow **design
anti-patterns**, which the operational-friction taxonomy missed. Surfaced after the user asked about
Code-node overuse and memory limits; both confirmed real (calibrated): Code nodes ~2.5:1 over native
conditional nodes, and a real n8n-pod **OOM** from Code nodes iterating >10k Postgres rows.

- **`/n8n-autopilot:feedback` is now a one-shot review flow** (default action): resolves the session
  transcript (`latest-transcript.js`), summarizes auto-captured signals, measures file-level design
  quality from `workflows/*.workflow.ts` (Code-vs-native, missing descriptions, overlapping node
  positions), does a qualitative pass, **LLM-redacts to neutral insights**, runs a deterministic PII
  gate, shows the result, and pushes. `interview` / `show` / `sync` remain as sub-actions.
- **Deterministic PII gate** `scripts/redact-check.js` — allowlist (known keys + signal names,
  numeric values, basename-only `repoLabel`) + denylist (email / abs-path / URL / long-digit / IBAN /
  token / configured customer names via `N8N_AUTOPILOT_PII_NAMES`). `sync.sh` runs it as a hard
  gate before every push (defense-in-depth on top of the LLM redaction).
- **`workflow-reviewer` checklist 10 → 15 points** — adds native-first (prefer IF/Switch/Filter/Set
  over Code), no silent failures (`continueOnFail`/`onError:continue`), memory/large-data (OOM),
  descriptions present, no overlapping nodes.
- **`capture-feedback.sh`** adds two transcript-detectable design signals: `memory_oom`,
  `continue_on_fail`.
- **`n8n-code-javascript` guidance** — new "When NOT to use a Code node (native-first)" section +
  OOM-on-large-data caveat; stopped listing "filtering" as a default Code use-case.

## [4.4.0] — 2026-05-29

### Added — `/n8n-autopilot:test-manual` + friction fixes from production-run analysis

Acts on the HIGH/MED improvement candidates surfaced by the v4.3.0 feedback-loop run analysis.
Conservative, additive fixes — the push-gate BLOCKING logic is unchanged.

- **New skill `/n8n-autopilot:test-manual <workflowId>`** — packages the non-HTTP-trigger
  (schedule/manual/errorTrigger) test detour (the #1 friction class, `non_http_test`=760) into one
  flow: resolves the n8n UI URL via `workflow present`, waits for the user-reported execution-id,
  then inspects the run via `execution get --include-data`. Read-only against the instance. Wired
  into `deploy` step 6 and CLAUDE.md.
- **Conflict-resolve churn reduced** (`conflict_resolve`=688, biggest friction) — push-gate BLOCKED
  messages and `deploy` step 3 now include a "back up local before pull" recipe (`cp <file>
  <file>.local-bak` → pull → diff → re-apply as a patch), so a local edit is re-applied as a small
  diff instead of being re-typed after `pull` overwrites it.
- **Validation guidance** (`validate_fail`=577) — `deploy` step 2 now points to the
  `n8n-validation-expert` guidance skill when validation fails (n8nac's validator text is terse and
  upstream-owned).

### Fixed

- `deploy` step 6 referenced a non-existent "step 9" for the non-HTTP manual-execution notice; now
  points to the new `/n8n-autopilot:test-manual` skill.

## [4.3.0] — 2026-05-28

### Added — Feedback Loop (SessionEnd capture + `/n8n-autopilot:feedback` skill + central GitHub sink)

A standardized way for the plugin to learn from real-world usage, grounded in an exhaustive analysis
of 33 Claude Code sessions from a real consumer repo.

- **Auto-capture** — new `SessionEnd` hook `scripts/capture-feedback.sh` silently extracts NON-PII
  friction signal counts from the session transcript (anchored taxonomy: `non_http_test`,
  `conflict_resolve`, `validate_fail`, `mcptrigger_detour`, `schema_gap`, `tool_error`, …) and
  appends one `kind:"event"` NDJSON record to `.n8n-autopilot/feedback/events.ndjson` in the consumer
  repo (gitignored). Fire-and-forget; never blocks shutdown; stores only counts + repo basename.
- **Interactive feedback** — new skill `/n8n-autopilot:feedback` runs a short process-feedback
  interview (questions derived from the top friction classes) → `process.ndjson`. `show` lists
  pending records; `sync` pushes everything centrally.
- **Central sink** — `sync` creates ONE labelled GitHub issue on `neurawork-git/n8n-autopilot-internal`
  via `gh issue create` (single transport path, no fallback). Consent-gated: every record is shown
  and a PII warning is given before pushing. A live feedback web server is a documented TODO
.
- **Nudge** — new `SessionStart` probe `scripts/check-feedback-pending.sh` emits an `INFO:` line
  (never `AUTOPILOT_ACTION_REQUIRED:`) when unsynced records exist.
- **Analysis finding** — the historical assumption that push-gate blocks were a top pain is NOT
  supported: `push_gate_block` is unobservable in historical transcripts (reclassified live-only).
  Bare-keyword grep was found to massively overcount (`"BLOCKED"`→`blockedBy` JSON, `"CONFLICT"`→SQL
  `ON CONFLICT`), so all heuristics are anchored to emitted strings.

## [4.2.2] — 2026-05-20

### Fixed — Skill frontmatter YAML parse errors + n8nac >= 2.2 quiet-skip in community-node check

Two bugs found via `claude --debug` log inspection in a real consumer repo:

**1. YAML parse failure in two skills** — Claude Code's loader reported `[WARN] Failed to parse YAML frontmatter` for `skills/n8nac-cheatsheet/SKILL.md` and `skills/build-workflow/SKILL.md`. Both skills were silently dropped from the session — only 14 of 16 plugin skills were loading. Root cause: an unquoted `description:` value contained `<word>: ` (e.g. "common workflows: lookup"), which js-yaml parses as a nested mapping. Fixed by wrapping both descriptions in quotes (single for one, double for the other due to embedded apostrophes / backticks) and replacing the inline colons with em-dashes where readability allowed.

**2. `check-installed-nodes` warned about missing `.env` even on bound workspaces** — n8nac >= 2.2 stores the API key in the secure manager store (`~/.n8n-manager/`), NOT in a workspace `.env`. The schema-coverage probe needs the key to query `/community-packages`, but it cannot retrieve it from the secure store. Pre-4.2.2 the script just printed "ℹ️  .env not found — skipping" on every session, which was misleading (looked like a setup issue, was actually the expected state). Now resolves auth in three tiers:

1. `.env` with `N8N_API_URL` + `N8N_API_KEY` — authoritative, runs the probe.
2. No `.env` but workspace bound — silent skip with explanatory note ("workspace bound (n8nac >= 2.2 keeps API key in secure store; cannot probe `/community-packages`). Run `/n8n-autopilot:pull-schemas` after installing new community nodes.").
3. Neither — quiet "skipping" (genuinely unconfigured).

No skill changes, no manifest changes beyond the version bump.

## [4.2.1] — 2026-05-20

### Fixed — SessionStart hook path resolution (consumer workspace, not plugin dir)

Two SessionStart-hook scripts still resolved their working directory to `$CLAUDE_PLUGIN_ROOT` (the plugin install dir under `~/.claude/plugins/cache/…`) instead of `$PWD` (the consumer repo where Claude Code is actually running). v3.7.1 fixed this for `check-credential-freshness.sh` and `check-workspace-migration.sh` but missed two others; this patch closes the gap.

- `scripts/check-schema-versions.sh` — now reads `schemas/_index.json` from the consumer workspace. Previously checked the plugin's own cache which never reflects the consumer's installed nodes.
- `scripts/check-installed-nodes.sh` — now reads `schemas/_index.json` and `.env` from the consumer workspace. This explains the long-standing "ℹ️ check-installed-nodes: .env not found — skipping." that the consumer repo saw on every session despite having a populated `.env` in its repo root.

Both files now follow the pattern documented in `check-credential-freshness.sh`: `REPO_DIR="$PWD"` with a comment block clarifying why `$CLAUDE_PLUGIN_ROOT` is the wrong primitive for workspace lookups.

No skill changes, no manifest changes beyond the version bump.

## [4.2.0] — 2026-05-20

### Added — n8nac knowledge skills (full CLI reference + curated cheatsheet)

Two new knowledge skills end the "agent fishing through `--help`" pattern:

**`n8nac-reference`** (`skills/n8nac-reference/`)
- Auto-generated, machine-walked `n8nac --help` tree.
- 74 subcommands across 26 top-level groups (workspace, env, instance-target, setup, credentials, credential, workflow, execution, skills, plus 14 root-level commands like `list`, `find`, `pull`, `push`, `promote`, `verify`, `test`, `test-plan`, `fetch`, `resolve`, `convert`, `convert-batch`, `mcp`, `update-ai`).
- Source of truth: **if a command is not in `reference.md`, it does not exist** — agents must not invent CLI surface.
- Regenerated via `scripts/dump-n8nac-help.sh` (re-run after any n8nac upgrade).
- Strict-mode help parser (column-3 anchor + alias-strip) keeps the file at ~1500 lines rather than the runaway 11000+ lines the loose parser produced on first attempt.

**`n8nac-cheatsheet`** (`skills/n8nac-cheatsheet/`)
- Curated "user intent → exact command" table, ~60 rows, grouped into Workspace, Multi-Environment, Instance Targets, Workflow Lifecycle, Testing & Execution, Credentials (CRUD + recipes), Schemas/Node Info, Telemetry.
- Highlights the singular `credential` vs. plural `credentials` distinction (most common "command not found" footgun), the push-gate bypass env var, and the n8nac >= 2.2 setup commands that replaced the removed `init` / `init-auth` / `init-project`.
- Gotchas section enumerates the 10 most common silent-failure patterns (project visibility, test trigger limits, mcpTrigger publish, archived read-only, etc.).

CLAUDE.md now has a "Knowledge skills" block above the cheat-sheet pointing at both, with the rule: **grep the cheatsheet → grep the reference → only then run `--help` live**. The `n8n-architect` companion skill is also linked as the canonical source for workflow authoring rules.

### Added — Multi-project awareness + push-gate (drift protection) + cheat-sheet

Three structural defects fixed after a real session showed Claude fishing through `--help`, inventing CLI subcommands (`skills list-credentials`), and injecting cross-project credential IDs:

**1. New skill `/n8n-autopilot:find-credential`** (`skills/find-credential/`)
- Search live credentials by name pattern, **scoped to the workspace-pinned project by default**.
- Flags: `--type <credType>`, `--project <name|id|all>`, `--exact`, `--json`.
- Returns table grouped by project + paste-ready TypeScript snippets.
- Shows count of cross-project matches as a footnote when default-scoped (no leak, but visible).
- Replaces the ad-hoc "`n8nac credential list --json | grep`" pattern that ignored project scope and routinely picked the wrong project's credential ID.

**2. New skill `/n8n-autopilot:find-project`** (`skills/find-project/`)
- Enumerates every n8n project visible on the active instance (derived from `credential list --json` → `shared[].name` / `shared[].id` — works without the Enterprise `/api/v1/projects` endpoint).
- Marks the workspace-pinned project, prints the exact `workspace set-project` command to switch.
- One audited instance shipped seven projects; agents had no way to see the others before this.

**3. Push-gate hook (`scripts/push-gate.sh`)** — wired into `hooks.json` PreToolUse(Bash)
- BLOCKS `npx n8nac push <file>` when `n8nac list --search <id>` returns status `CONFLICT` / `MODIFIED_BOTH` / `DIVERGED` / `REMOTE_ONLY`. Hook auto-runs `n8nac fetch <id>` first, so the verdict is always against fresh remote state.
- BLOCKS `npx n8nac resolve <id> --mode keep-current|keep-local|local-wins` unconditionally — this command silently overwrites remote with local.
- Single bypass: `N8N_AUTOPILOT_ALLOW_LOCAL_WINS=1 <re-run command>` (requires explicit user authorization that remote changes are to be discarded).
- New workflows (file with no `id:` field) are never blocked.

**4. `sync-credentials --fix-workflows` now project-scoped by default**
- Joins workflow credential references against ONLY credentials owned by the active workspace project. Cross-project name collisions no longer rewrite IDs into the wrong project.
- Header now reports `Project scope: <name> (<id>)` and "Skipped N credential(s) owned by other projects" so the scope is visible in every run.
- New flag `--all-projects` disables the filter (rare, used when migrating workflows between projects).

**5. CLAUDE.md cheat-sheet at the top of the file**
- "User asks X → run Y" table covering every common request (find credential, list projects, switch project, build, deploy, fix creds, inventory, data-tables, executions, etc.).
- Push-gate section documenting block conditions and the override env var.
- Multi-project rule stated up front: every credential / workflow operation runs in the workspace-pinned project's scope; verify the pin before touching credentials.

**6. `check-mcps` skill + `setup-check.sh` Section 6** now print the project visibility table on every health check / SessionStart, so multi-project state is visible without an explicit query.

**Why this matters (real incident pattern):** workspace pinned to project A, instance has projects A–G, `n8nac credential list --json` returns creds from all visible projects. Agent matches by name only → injects credential ID from project F into a workflow in project A → push succeeds, runtime fails with "credential not accessible". After 4.2.0: `find-credential` shows only project A by default, `sync-credentials --fix-workflows` will not rewrite cross-project IDs, push-gate refuses to silently overwrite remote changes.

## [4.1.0] — 2026-05-19

### Changed — skills now invoke bundled scripts, no inline executable code

Three skills previously embedded large inline bash/node blocks (50+ lines of executable code in the SKILL.md body). That pattern caused Claude to read the skill, paraphrase the logic, and re-implement it ad-hoc — which in turn led to skills "meandering" (writing one-off helper scripts into the consumer repo, probing wrong API paths, misclassifying nodes). The skill body should be intent and pointers; the code lives in colocated scripts.

Per the skill-creator norm (`skill-name/scripts/`), skill-specific executable code now lives inside the skill folder itself.

**`pull-schemas`** — new bundled `scripts/`:
- `discover-types.sh` — extracts node types from `workflows/**/*.workflow.ts`
- `fetch-one.sh` — fetches one indexed node via `npx n8nac skills node-info` (exit 1 = "not in n8nac index, try Stage 2")
- `fetch-pkg.js` — extracts every exported node class from a published npm package directly
- `rebuild-index.js` — walks `schemas/nodes/**` and rebuilds `schemas/_index.json`
- `run.sh` — orchestrator. The skill body now just says `bash $CLAUDE_PLUGIN_ROOT/skills/pull-schemas/scripts/run.sh [flags]`.

**`inventory`** — new bundled `scripts/aggregate.js`:
- Walks workflows, extracts node types / triggers / LLM models / credentials / workflow names, classifies them, renders the Markdown report. No more inline grep+xargs+node+jq pipelines that Claude had to stitch together.
- Best-effort enriches the Summary header with remote counts via `npx n8nac list --json --include-archived`.

**`sync-credentials`** — new bundled `scripts/`:
- `list.js` — fetches `npx n8nac credential list --json`, prints a clean table + ready-to-paste TypeScript snippets.
- `fix-workflows.js` — the rewrite logic: tolerant block-parsing regex, surgical `id:` replacement inside each matched `credentials: { … }` block (never global), conflict + orphan reporting. The previous skill body asked Claude to "use a tolerant regex — recommended approach: a node script with proper TS-source parsing"; now there is one.

All three SKILL.md bodies are now thin pointers (~50 lines each) — when to invoke, which flag does what, where the scripts live. No executable code in the skill prose.

Verified end-to-end against a real consumer repo: pull-schemas pulled 16 core schemas, inventory rendered the report, sync-credentials --fix-workflows --dry-run correctly detected 16 stale credential references plus 5 orphans.

## [4.0.0] — 2026-05-19

### Breaking

- **n8n-autopilot is now CLI-only.** All `mcp__n8n-as-code__*` tool references removed across `build-workflow`, `deploy`, `pull-schemas`, `check-mcps`, `sync-credentials`, and `agents/n8n-researcher.md`. The namespace never had a stable upstream source — the npm `n8nac mcp` entry-point crashes in every published version (missing `mcp` package dependency in `@n8n-as-code/skills`), and Etienne Lescot's `n8n-as-code` plugin ships skill knowledge, not an MCP server. All schema research / node-info / validation now goes through `npx n8nac skills …`.
- **Companion plugin `n8n-as-code@n8nac-marketplace` (Etienne Lescot) is now expected.** It provides the `n8n-architect` skill that owns Schema-First Research, Workflow Authoring Rules, AI/LangChain rules, Common Mistakes, Operating Loop, etc. n8n-autopilot delegates these and focuses on what it uniquely adds: workspace lifecycle (`init-repo`), build pipeline orchestration (`build-workflow`), deploy with auto-fix loop (`deploy`), `pull-schemas` Stage 2 npm-extraction, `sync-credentials --fix-workflows`, `inventory`, `data-tables`, and SessionStart diagnostics.
- **Four redundant knowledge skills removed** because they overlap with `n8n-architect`:
  - `n8n-workflow-patterns/`
  - `n8n-node-configuration/`
  - `n8n-validation-expert/`
  - `n8n-expression-syntax/`
  Kept: `n8n-code-javascript`, `n8n-code-python` — both genuinely cover Code-node specifics that `n8n-architect` does not touch.
- **`agents/n8n-researcher.md` removed.** Build-workflow Phase 0 calls the CLI directly (`npx n8nac skills search/node-info/related/examples`); Etienne's `n8n-architect` is the canonical researcher.
- **`.mcp.json.example` + `skills/init-repo/assets/templates/mcp.json` removed.** No `.mcp.json` is scaffolded into new repos.
- **`init-repo` scaffolds 4 files instead of 5** (CLAUDE.md, README.md, .gitignore, .env.example) — `.mcp.json` is gone.
- **`check-mcps` skill rewritten.** No more "MCP tool registration" check (no MCP). Now verifies: n8nac CLI version, workspace bound, companion plugin enabled.

### Fixed

- **`claude plugin path` references removed everywhere.** That command does not exist in the Claude Code CLI (`claude plugin --help` shows only `list/install/uninstall/marketplace/update`). Replaced with: `$CLAUDE_PLUGIN_ROOT` env var (in plugin-context scripts), slash-command pointers (`/n8n-autopilot:check-mcps`), or "runs auto via SessionStart hook" (for verification hints). This was a pre-existing bug from Jochen's era that earlier versions silently inherited.
- **MCP version pinning rolled back.** v3.7.0 pinned `.mcp.json` invocations to `n8nac@2.2.0` after observing 2.2.1 crashes. Investigation showed `npx n8nac mcp` crashes in every published n8nac version — `require('mcp')` without a declared dep is an architectural issue, not a regression. Pinning was Symptom-treatment that did not help; removed.

### Added

- **Companion-plugin health check in `setup-check.sh`.** Warns when `n8n-as-code@n8nac-marketplace` is not enabled in user settings, with install instructions inline.

### Migration guide for consumer repos (3.x → 4.0)

1. Install the companion plugin (one-time):
   ```bash
   claude plugin marketplace add EtienneLescot/n8n-as-code
   claude plugin install n8n-as-code@n8nac-marketplace
   ```
2. Bump n8n-autopilot: `claude plugin install n8n-autopilot@n8n-autopilot` (auto-pulls 4.0.0).
3. Remove any workspace-local `.mcp.json` that only contained the `n8n-as-code` entry — it was never functional in any version. If your `.mcp.json` has other entries (e.g. `n8n-mcp@latest` from czlonkowski), drop only the `n8n-as-code` block.
4. Verify: `/n8n-autopilot:check-mcps`. Expect green on all rows.

## [3.7.1] — 2026-05-19

### Fixed
- **SessionStart hooks looked at the wrong directory.** Both `check-workspace-migration.sh` and `check-credential-freshness.sh` resolved `REPO_DIR` from `$CLAUDE_PLUGIN_ROOT`, which points at the plugin install path — not the consumer workspace. Result: workspace-local `n8nac-config.json` and stale credential refs in consumer repos were silently invisible (false negatives). Now both scripts use `$PWD`, which the hook runtime sets to the user's workspace.
- **`check-workspace-migration.sh` was content-blind.** Now reads the `version` field of any found `n8nac-config.json` and surfaces the right reason: `version: 1 | 2` → pre-2.2 schema (legacy data); `version: 4` → schema is current but the file is in the wrong location for n8nac 2.2 (which expects user home). Both cases still resolve to the same `workspace migrate-v1 --write` command.
- **Path-quoting bug in the new version probe.** Inline `node -e "require('$WIN_PATH')"` failed under Git-Bash on Windows due to backslash handling. Switched to reading the file with `cat … | node -e "JSON.parse stdin"` for portability.

## [3.7.0] — 2026-05-18

### Changed (breaking for repos still on n8nac < 2.2)
- **n8nac reference version pinned to 2.2.1** (minimum 2.2.0). Single source of truth: `REFERENCE_N8NAC_VERSION` constant in `scripts/setup-check.sh`. README badges, root `CLAUDE.md`, `init-repo` skill, and `plugin.json` all reference this.
- **`init-repo` skill rewritten for the v2.2 setup flow.** The removed n8nac commands `init` / `init-auth` / `init-project` no longer appear anywhere in the plugin. Replacement flow:
  1. `npx n8nac setup --mode connect-existing --host <url> --api-key-stdin --json`
  2. `npx n8nac workspace pin-instance --instance-id <id>`
  3. `npx n8nac workspace set-sync-folder workflows`
  4. Optional: `npx n8nac workspace set-project --project-name <n>`
- **`scripts/setup-check.sh` rewritten.** Workspace-binding check no longer looks for `./n8nac-config.json` (file relocated to user home in n8nac 2.2). Now calls `npx n8nac workspace status --json` and distinguishes `ready` / `dry-run` (migration pending) / unknown. Live-connectivity probe pulls the host from the workspace-status JSON instead of grepping a file.
- **`scripts/check-credential-freshness.sh`** init hint updated to `npx n8nac setup --mode connect-existing`.
- **Templates updated.** `skills/init-repo/assets/templates/`: removed `n8nac-config.json.example`; the file is no longer scaffolded into consumer repos. `gitignore` keeps the legacy entries (for the migrate-v1 transition window) but documents why. `CLAUDE.md` + `README.md` setup sections rewritten for the new flow.
- **Plugin docs (`CLAUDE.md`, `README.md`, `README.de.md`)** synced to the new flow. Added a top-level "Reference n8nac version" callout pointing at `REFERENCE_N8NAC_VERSION`.

### Added
- **`build-workflow` Phase 0 — Step 0 added: community-template lookup is now mandatory before node-by-node discovery.** `npx n8nac skills examples search/info/download` now appears at the top of the Phase 0 tools table and as Step 0 in the pipeline. Threshold: if a template matches ≥70 % (same trigger family + target service + comparable transformations), download it as the seed and run discovery only for added/changed nodes. Adapting a validated template is cheaper, less hallucination-prone, and lands on a community-proven pattern. The Phase-0 sub-agent (`n8n-researcher`) already had these tools — this change wires them into the Lead-Claude pipeline doc so the sub-agent actually gets asked to use them.
- **`scripts/check-workspace-migration.sh` + SessionStart hook.** New informational diagnostic that flags two migration-pending states: (1) legacy `./n8nac-config.json` in the repo (suggests `workspace migrate-v1 --write`); (2) `workspace status` returning `dry-run` / `migration-required` (suggests `workspace migrate --write`). Surfaced verbatim to Claude; deliberately NOT in the `AUTOPILOT_ACTION_REQUIRED` auto-execute list because migrations move files on the user's filesystem and should be run consciously. Wired into `hooks/hooks.json` after `check-credential-freshness`.
- **`npx n8nac workflow present <id>` integration.** The `deploy` skill (mcpTrigger publish notice) and the manual-execution notices in root `CLAUDE.md` now resolve the user-facing URL via `workflow present` instead of string-concatenating `<host>/workflow/<id>`. Avoids host-mismatch bugs across multi-env setups.
- **Credentials recipe / inventory surface (n8nac 2.2).** `sync-credentials` skill documents `npx n8nac credentials recipes`, `credentials inventory`, `credentials ensure <recipeId>`, and `credentials test` for richer reporting and shared-recipe creation. Root `CLAUDE.md` "ALWAYS use n8nac" section lists them as first-class commands.
- **Workspace-binding commands** (`workspace set-sync-folder`, `workspace set-project`, `workspace migrate`, `workspace migrate-v1`) added to the root `CLAUDE.md` operations list and both READMEs' command tables.
- **Promote** (`npx n8nac promote --from --to`) **deliberately not yet integrated.** Multi-environment workflow promotion is in n8nac 2.2 but most consumer repos don't have multiple environments. Will revisit when there's a real user.

### Migration guide for existing consumer repos

1. Bump n8nac: `npx clear-npx-cache && npx n8nac@latest --version` (expect ≥ 2.2.0).
2. If `./n8nac-config.json` exists in the repo: `npx n8nac workspace migrate-v1 --write` (one-shot; moves config to `~/n8nac-config.json` + `~/.n8n-manager/`).
3. If `npx n8nac workspace status --json` returns `status: "dry-run"`: `npx n8nac workspace migrate --write`.
4. Verify: `bash scripts/setup-check.sh` should print "All checks passed".

## [3.6.1] — 2026-05-18

### Added
- **`README.de.md`** — full German translation of the README. Language-switcher banner at the top of both READMEs follows the GitHub `README.<locale>.md` convention.

## [3.6.0] — 2026-05-18

### Added
- **`/n8n-autopilot:data-tables`** — new skill for managing n8n DataTable resources (CRUD on tables, columns, rows) via the public REST API at `/api/v1/data-tables`. PreToolUse curl-block has an explicit carve-out for this single path; all other API endpoints stay blocked.
- **Auto-Reactions on SessionStart** — hook scripts now emit machine-parsable `AUTOPILOT_ACTION_REQUIRED: <slash-command>` lines. Claude runs the literal command without asking the user, when the action is safe and idempotent. Mapping is documented in `CLAUDE.md`.
- **`--packages` flag in `/n8n-autopilot:pull-schemas`** — targets specific npm community-node packages for refresh (used by the auto-reaction signal).
- **`--fix-workflows` mode in `/n8n-autopilot:sync-credentials`** — rewrites stale credential IDs in local `.workflow.ts` files by matching credential name.
- **`/n8n-autopilot:init-repo`** — one-command repo bootstrap (was added in 3.5.0 prep, shipped together).
- **`/n8n-autopilot:inventory`** — aggregates node/LLM/credential usage from local workflows into `docs/INVENTORY.md`.
- **`docs/OVERVIEW.md`** — one-page summary.
- **`CHANGELOG.md`** — this file.

### Changed
- **All skills now spec-conformant per skill-creator standard.** Bundled reference docs moved from sibling-of-`SKILL.md` into `references/` subdirectories. TOCs added to large reference files (>300 lines). Every skill has explicit `user-invocable: true/false` in its frontmatter.
- **`n8nac` minimum version bumped to 2.2.0** in `scripts/setup-check.sh`, `README.md`, `docs/OVERVIEW.md`, `docs/ARCHITECTURE.md`. The `instance` / `switch` CLI vocabulary from 1.x is replaced by `env|environment` + `workspace pin-instance` in 2.x — all docs updated.
- **`marketplace.json` + `plugin.json`** synced to `3.6.0`.
- **`scripts/check-schema-versions.sh`** no longer calls `check-installed-nodes.sh` at the end (duplicate-fire per SessionStart). `setup-check.sh` Section 7 remains the sole caller.
- **`build-workflow` skill**: removed duplicate `test-plan` call from Path A, fixed wrong tool name (`validate_workflow` → `validate_n8n_workflow`), pulled Phase 2 fully into English, integrated naming conventions inline.
- **`docs/ARCHITECTURE.md`** rewritten to reflect the post-3.5 architecture (sole n8nac backend, no Native Instance MCP).

### Removed
- **Orphan files** — `skills/build-workflow/NAMING.md` (content folded into `build-workflow` Phase 1) and `skills/n8n-validation-expert/VALIDATION_RULES.md` (content folded into `n8n-validation-expert` body; the file's unused `paths:` frontmatter was a no-op).

### Renamed
- **`scripts/ensure-mcp-available.sh` → `scripts/ensure-mcp-trigger-setting.sh`** — the script guards the workflow setting `availableInMCP`, not MCP server reachability. Docs + hook reference updated.

## [3.5.x] — internal, not released to marketplace

3.5.0 introduced the `init-repo` skill and the inventory-freshness check. Marketplace was still pinned to 3.4.0; the 3.5.x line is rolled into 3.6.0 for the public release.

## [3.4.0] — 2026-04-13

### Removed
- **Native Instance MCP (16-Tool-SDK)** — the prior "Drei-Säulen-Architektur" (n8nac + Native Instance MCP + Plugin) collapsed to two pillars. n8nac is now the sole backend for all instance operations. All references in `docs/ARCHITECTURE.md` and `docs/OVERVIEW.md` removed.

### Changed
- **Adapted to n8nac 1.8.1** — structured JSON flags (`--strict --json`), min-version bump.

### Added
- **`check-credential-freshness.sh`** SessionStart hook.
- **`scripts/check-installed-nodes.sh`** — detects community nodes installed on the instance but missing from the local schema cache.
- **`ensure-mcp-available.sh`** PreToolUse hook — auto-guards the workflow setting `availableInMCP` for `mcpTrigger` pushes.

## [3.2.0 – 3.3.x] — community-node staleness + execution mandate

- Auto-fetch missing community node schemas + staleness detection.
- `execute/test` made mandatory in `build-workflow`; mcpTrigger publish lifecycle documented.

## [3.1.0]

- Upgraded n8nac to 1.5.5.

## [3.0.0]

- Integrated `n8n-instance` MCP as Tier-2 enrichment layer (5 → 16 tools). Later removed in 3.4.0.

---

For commit-level detail, see `git log` on `main`.
