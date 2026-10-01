# Hook Gates — Push-Gate, Push-Lint-Gate & Env-Gate

Full mechanism + rationale for the `PreToolUse` gates. CLAUDE.md carries the
one-line summary; this is the load-bearing detail.

## How the gates receive the command (read this before touching hooks.json)

One entry in `hooks/hooks.json` — `matcher: "Bash|PowerShell"` → `scripts/pretooluse-gate.sh` —
reads the hook input Claude Code delivers as **JSON on stdin** (`tool_input.command`) and runs the
gates in order: curl-block → `enforce-env.sh` → `push-gate.sh` → `push-lint-gate.sh` →
`ensure-mcp-trigger-setting.sh`. Exit 2 from any gate blocks the tool call and its stderr reaches
the agent.

Until 5.5.0 every gate read `$CLAUDE_TOOL_INPUT`. That variable does not exist (the hooks
reference documents stdin JSON and no such env var), so `INPUT` was empty and every gate exited 0.
Measured over 120 days of customer-repo sessions: dozens of `npx n8nac push` calls, direct `curl`
against `/api/v1`, un-pinned sessions — not one `[push-gate]`, `[enforce-env]` or `[push-lint]`
line in any tool result. The gates only ever fired when invoked by hand with an argument. The
PowerShell tool was not matched at all. `bash scripts/test-pretooluse-gate.sh` feeds the dispatcher
stdin JSON for both tools and asserts the blocks; run it after any hook change.

---

## Push-Gate (drift protection — `scripts/push-gate.sh`)

The `PreToolUse` hook blocks two operations by default:

1. **`npx n8nac push <file>`** when `npx n8nac list --search <id>` reports status
   `CONFLICT`, `MODIFIED_BOTH`, `DIVERGED`, or `REMOTE_ONLY` — i.e. remote has changed
   since the last local fetch.
2. **`npx n8nac resolve <id> --mode keep-current|keep-local|local-wins`** — always
   blocked, because it overwrites remote with local in one step.

Bypass (single command, only after explicit user authorization that the remote change
should be discarded):

```bash
N8N_AUTOPILOT_ALLOW_LOCAL_WINS=1 <re-run the n8nac command>
```

Default reconciliation path when push is blocked:
1. `npx n8nac pull <id>` — remote wins, sync local
2. Re-edit the local file with your intended change
3. `npx n8nac push <id> --verify` again

The hook auto-runs `npx n8nac fetch <id>` before judging status, so the verdict is always
against fresh remote state. Workflows without an `id:` field (new creations) are never blocked.

### Deploying several locally-edited workflows at once

Resolving file by file is the intended cost when the remote genuinely changed — but not every batch is
that case. Work through them in this order:

1. **Self-inflicted drift?** If *this session* activated the workflow, the remote hash moved on the
   `active` flag alone. That is not content drift: `npx n8nac fetch <id>` re-baselines it (cache-only,
   never touches the local file) and the push goes through. No resolve, no data at risk. This covers
   the most common batch — a stack that was just activated.
2. **Genuinely stale local?** `pull` → re-apply your edit → `push --verify`, per file. Slow on purpose:
   somebody else's edit is on the other side.
3. **Local really is authoritative for the whole batch** (you have confirmed the remote changes are
   disposable): export the bypass once for the loop rather than per command.

```bash
export N8N_AUTOPILOT_ALLOW_LOCAL_WINS=1
for f in workflows/**/*.workflow.ts; do npx n8nac push "$f" --verify; done
unset N8N_AUTOPILOT_ALLOW_LOCAL_WINS   # do not leave it set — it disarms the gate for the session
```

There is deliberately **no** "local supersedes remote" auto-detection. n8nac reports a status word, not
ancestry — nothing available here can prove the remote is an ancestor of local rather than a divergent
edit, and a wrong guess silently destroys someone's UI change. The decision stays with a human;
`export` just stops it being asked once per file.

### Self-inflicted drift: your own `workflow activate`

`npx n8nac workflow activate <id>` mutates the remote (`active: false → true`) and therefore changes
the remote sync hash. A `MODIFIED_BOTH` right after your own activation is **not** foreign remote work
— nobody edited the workflow in the UI. Do **not** reach for `resolve --mode keep-current` (that is the
bypass this gate exists to prevent, and it also blocks `pull`, so the situation looks unresolvable).

Correct sequence: `npx n8nac fetch <id>` to re-baseline the cache (cache-only, never touches the local
file) → `push --verify` again. Better yet, order the work so **activation comes after the last push**;
`build-workflow-v2` / `build-stack-v2` do this by construction (`deferActivation` + a bottom-up
Activate phase at stack level).

---

## Env-Gate (one env per session — `scripts/enforce-env.sh`)

A session works in exactly ONE n8n env (instance + project). The `PreToolUse` hook
**fail-closed BLOCKS** any instance-touching `npx n8nac` command that resolves to NO explicit
env — otherwise it would silently hit the mutable GLOBAL active env (`env use`), which is shared
across sessions and wrong when sessions target different projects.

An env is "resolved" (command allowed) when ANY of these holds:
- session default set: `export N8NAC_ENVIRONMENT=<env-name>` (the normal per-session pin), or
- inline: `N8NAC_ENVIRONMENT=<env-name> npx n8nac …`, or
- per-call flag: `npx n8nac --env <env-name> …`.

Local-only subcommands never touch an instance and are never gated:
`skills`, `convert`, `convert-batch`, `workspace`, `env`, `setup`, `setup-modes`, `telemetry`,
`update-ai`, `help`, `--version`. Everything that contacts the instance (`list`, `find`, `pull`,
`push`, `fetch`, `verify`, `test`, `test-plan`, `resolve`, `promote`, `execution`, `credential[s]`,
`workflow`) is gated.

`npx n8nac env list --json` lists envs + their projects. n8nac itself throws
`Unknown workspace environment: <name>` on a bogus env name (so a typo fails closed, never silently
falls back). The SessionStart hook `scripts/report-session-env.sh` prints the active session env
(name + host + project) so you always know where you are. **Verified routing**: `N8NAC_ENVIRONMENT`
and `--env` both route instance commands to the named env's instance, independent of the global active.

**Clobber-guard:** `enforce-env.sh` also **blocks `env use` / `env pin` unconditionally** — those
mutate the machine-GLOBAL active env (shared across all sessions) and are the exact operation that
lets one session re-point another's un-pinned commands. Sessions pin via `N8NAC_ENVIRONMENT`, never
`env use`. Bypass for a deliberate machine-default change only: `N8N_AUTOPILOT_ALLOW_ENV_USE=1 npx
n8nac env use <name>`. **Gotcha:** `workspace status` is env-blind (reflects the global active, ignores
the session var) — use `env status` / `env list --json` for session-aware resolution.

Full model + empirical isolation test (`scripts/test-env-isolation.sh`, 17 assertions):
**[`session-env`](../../skills/session-env/SKILL.md)** (`/n8n-autopilot:session-env`).

## Push-Lint-Gate (design quality — `scripts/push-lint-gate.sh` + `scripts/lint-workflow.py`)

Runs on every `npx n8nac push <file>` after the drift Push-Gate. Fail-closed, deterministic, no LLM.
The `workflow-reviewer` agent describes the same rules in prose, but it runs inside `safe()` in the
build pipelines, so a crashed reviewer opens the gate. This hook is the part of the checklist that
code can decide.

Three stages, all must pass:

1. **Every node type + `typeVersion` must exist on the instance.** The gate compiles the file once
   (`npx n8nac convert`) and runs `node scripts/instance-node-check.mjs <json>`,
   which asks the instance's own MCP `get_node_types` per type@version. For CORE packages
   (`n8n-nodes-base`, `@n8n/n8n-nodes-langchain`) it blocks on "Version 'X' not found" and on
   "Node type 'T' not found" — the latter also hits hidden/deprecated core nodes
   (`spreadsheetFile`, `function`, `itemLists`), which is intended. Community nodes only warn: the
   instance catalogue does not list every installed one. It also blocks when the check cannot run
   (native MCP not configured for the session env, unreachable, token rejected). n8nac's own push
   preflight is not enough: without the instance tool `validate_node_config` it only warns and
   validates against its bundled catalogue, which is stamped for a different n8n version (#85, #82,
   #62). Setup and the n8nac traps behind this: [testing.md](testing.md).
1b. **Every top-level parameter must exist for the node's `typeVersion`** —
   `python scripts/param-version-check.py <json>`. n8n gates parameters per version through
   `displayOptions.show/hide['@version']`; `n8nac skills validate` checks the key's name, not its
   gate, so `formTrigger` 2.5 with a top-level `path` passed every gate and answered 500 at runtime
   (#94), and the Anthropic model's `model` parameter changed shape at 1.3 unnoticed (#84). The
   script reads the version-gated schema through n8nac's own `NodeSchemaProvider` for every uncached
   type in ONE process (`scripts/node-schemas.mjs` via `npx -p n8nac node`, ~2 s cold, then a 24 h
   cache per type under the temp dir — `skills batch` renders docs and cannot serve this) and blocks
   a key that exists only in OTHER versions, naming the versions that have it. A key in no version is a warning (the validator's territory); a type node-info
   does not know is a warning (stage 1 judges it). `python scripts/param-version-check.py --selftest`.
2. **`python scripts/lint-workflow.py <json>`** on the same compiled workflow:

| Rule | Level | Catches |
|---|---|---|
| `empty-compile` | block | compiled JSON has 0 nodes — transformer dropped the class (#20) |
| `no-trigger` / `dead-trigger` | block | no trigger, or a trigger with no outgoing edge |
| `orphan` | block | non-trigger node with no incoming edge and not an AI sub-node — n8n never runs it (#93) |
| `masked-error` | block | `continueOnFail` / `onError: continueRegularOutput` whose main output does not feed an If/Switch/Filter/Code that tests `$json.error` — the failed item flows on as a success (an `executeWorkflow`/Postgres step reported "done" for work that never happened). Since 5.6.0 a `notes` justification no longer exempts |
| `error-unwired` | block | `onError: continueErrorOutput` whose error output has no edge — the `.error()` edge n8nac emits is a silent no-op (#57) |
| `no-error-strategy` | block | top-level workflow (trigger is not `executeWorkflowTrigger`/`errorTrigger`) with external calls (`httpRequest` or any credentialed node) and neither `settings.errorWorkflow` nor a wired error output — a failure vanishes into the execution list |
| `expression` | block | `=`-prefixed value with unbalanced `{{ }}` or unbalanced brackets inside an expression (#92) |
| `empty-code` | block | Code node without `jsCode` / `pythonCode` |
| `no-respond` | block | webhook `responseMode: responseNode` without a `respondToWebhook` node |
| `not-mcp-testable` | block | `settings.availableInMCP` is not `true` — the test path cannot execute the workflow |
| `retry-missing` | warn | `httpRequest` without `retryOnFail` — one transient 5xx fails the run (#88) |
| `code-env-access` | warn | Code node reads `$env` or `require()`s a builtin — hardened instances deny both at runtime (#97) |
| `code-heavy` | warn | Code nodes > 50 % of functional nodes (#76) |
| `no-sticky` | warn | no stickyNote |
| `overlap` | warn | two nodes < 80 px apart on both axes |

**Inside the build pipelines** (`build-workflow-v2` greenfield + edit) a `[push-lint] BLOCKED` from
the deployer is a fix loop, not a deploy failure: the author fixes exactly the BLOCK lines, the
validator re-checks, the deployer pushes again (max 3 cycles, `stage: 'lint'` on exhaustion).
A `[push-gate]` drift block or an `[enforce-env]` block still ends the build at `stage: 'deploy'`
with `blockedBy` set. Regression: `node scripts/test-pipeline-gates.mjs` cases 8–10.

Stage 1 over the 78 local workflows of the internal instance: 77 pass, one blocks on the deprecated
`spreadsheetFile` node. Four community nodes (`n8n-nodes-soap`, `n8n-nodes-close-crm`,
`n8n-nodes-pandadoc`, …) answered "not found" — PandaDoc ran successfully on the instance the same
day, so these are catalogue gaps and stay warnings.

Stage 2 was calibrated on the same 78 workflows before `not-mcp-testable` existed:
58 passed, and the two false-positive classes found (`n8n-nodes-base.form` pages counted as
triggers, JSON-schema strings ending in `}}`) are fixed. Every remaining blocker was a real defect:
unwired error outputs, orphan nodes, form workflows whose trigger has no edge, three sub-workflows
compiling to 0 nodes. Existing workflows with `availableInMCP: false` now need the flag flipped on
their next push.

**Fix path:** read the `BLOCK` lines (rule · node · message), edit the `.workflow.ts`, push again.
Bypass only after the user explicitly accepted shipping a failing workflow:
`N8N_AUTOPILOT_SKIP_LINT=1 <cmd>`. Self-check: `python scripts/lint-workflow.py --selftest`.
