---
name: plugin-testing
description: "The ONLY supported way to test changes to the n8n-autopilot plugin itself: commit → push to the private repo → install FROM that repo → restart → verify registration. Use whenever a plugin change (agent, skill, hook, script) must be exercised in a real session. Hard rule: no cache hand-copying, no directory-pointer marketplace, no hand-edited settings.json. Push to repo, install from there, nothing else."
argument-hint: ""
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash(git:*), Bash(claude:*), Workflow
---

# Plugin Testing — push to repo, install from there, nothing else

> **THE RULE.** A change to this plugin (agent def, skill, hook, script, manifest) is tested in exactly
> one way: **commit it, push it to `neurawork-git/n8n-autopilot-internal`, install the plugin FROM that
> GitHub repo, restart, verify.** Nothing else counts. A change you have not pushed-and-installed has not
> been tested — you are looking at stale or inconsistently-registered state.

## Why (lessons paid for)

- **Hand-copying files into `~/.claude/plugins/cache/.../<version>/`** registers inconsistently: agents
  silently fail to appear, `/reload-plugins` does not pick up newly-added agents, and you end up with
  two plugins thinking different things. NEVER do it.
- **A directory-pointer marketplace** (`extraKnownMarketplaces … source: directory`) drifts from the
  committed truth and produces dual stale installs. Do not use it for testing.
- **Hand-editing `.claude/settings.json` `enabledPlugins`** desyncs the install records. Use the CLI
  (`claude plugin enable/disable`).
- **`/reload-plugins`** is NOT sufficient for newly-added agents/hooks — only a full session restart
  reliably registers them.

## The flow

### 1. Commit + push + bump version
The installer is **version-keyed**: `install`/`update` no-op if the version already present. So every
test cycle bumps the version.
```bash
# bump .claude-plugin/plugin.json + .claude-plugin/marketplace.json version (e.g. 4.8.0 -> 4.8.1)
git add -A
git commit -F - <<'MSG'
<type>: <subject>            # clean Conventional Commit — NO leading "@", umlauts correct (ä/ö/ü/ß)

<body>

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
MSG
git log -1 --format='[%s]'   # verify subject is clean (no stray @)
git push origin main
```

### 2. Register the repo marketplace (once) — point at `-internal`, mind the name collision
We push to and install from **`neurawork-git/n8n-autopilot-internal`** (the dev repo). Its
`marketplace.json` name is `n8n-autopilot` — the **same name** as the public release marketplace
(`neurawork-git/n8n-autopilot`). Two marketplaces cannot share a name, so:
```bash
# if a `n8n-autopilot` marketplace already points at the PUBLIC repo, remove it first:
claude plugin marketplace list                      # check the Source of `n8n-autopilot`
claude plugin marketplace remove n8n-autopilot      # only if it points at the public repo / a directory

claude plugin marketplace add neurawork-git/n8n-autopilot-internal   # GitHub source = single truth
```
Never add a `directory` source for this name (that is the cache-drift trap).

### 3. Pull the new version + install
```bash
claude plugin marketplace update <marketplace-name>     # re-pull the just-pushed commit
claude plugin install n8n-autopilot@<marketplace-name> --scope user
# (or `claude plugin update n8n-autopilot@<marketplace-name>` once installed)
```

### 4. Restart the session
Plugins — especially new agents and hooks — register at **session start**. Restart fully.
`/reload-plugins` does not reliably register newly-added agents.

### 5. Verify registration (post-restart)
Run the verification probe — a short Workflow that confirms the install is real:
```js
// for each expected agentType, confirm it resolves + that its skills: loaded
phase('Verify')
const AGENTS = ['n8n-researcher','n8n-node-verifier','n8n-comprehender','n8n-author',
                'n8n-validator','n8n-deployer','n8n-tester','n8n-mirror']
const r = await parallel(AGENTS.map(a => () =>
  agent(`Reply with exactly: OK ${a}. Then name one skill you have loaded from your context.`,
        { agentType: `n8n-autopilot:${a}`, label: a }).catch(e => ({ a, error: String(e).slice(0,120) }))))
return r
```
- Every agent resolves (no "agent type not found") ⇒ registration clean.
- Each names a loaded skill ⇒ `skills:` pass-through works.
- Also confirm SessionStart hooks fired (look for `report-session-env` / `check-mirror-drift` output).

## Cleaning up a messy state (one-time)
If dual/stale installs or a directory-pointer marketplace exist:
```bash
# uninstall is BLOCKED while the plugin is enabled at PROJECT scope (.claude/settings.json).
# `--scope local` does NOT clear that — use --scope project:
claude plugin disable n8n-autopilot@<mp> --scope project
claude plugin uninstall n8n-autopilot@<mp>                     # removes stale install records (per version)
claude plugin marketplace remove <directory-pointer-name>     # drop any directory pointer / public-repo mp
# then: marketplace add (github -internal) -> install -> restart -> verify
```
Never resolve a messy state by editing cache files or `settings.json` by hand — only the CLI
(`claude plugin disable/enable/uninstall`, `claude plugin marketplace remove/add`).

## Definition of done
A plugin change is "tested" only when: pushed to `main`, installed from the GitHub marketplace at the new
version, session restarted, and the verification probe is green (all agents resolve, skills load, hooks fire).
