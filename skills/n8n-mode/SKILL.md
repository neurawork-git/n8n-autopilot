---
name: n8n-mode
description: Switch the per-session n8n mode on, off, or show its status. While it is off, n8n-autopilot stays out of the session (no SessionStart probes, no feedback Stop gate, no feedback capture) — the safety gates on n8nac commands always apply. Use when the user says "n8n mode on", "n8n-Modus an", "start n8n work", "I want to work on n8n workflows now", "turn n8n off", "why does n8n-autopilot fire here", or before n8n work in a project monorepo.
argument-hint: "[on | off | status]"
user-invocable: true
allowed-tools: Bash(bash:*)
---

# n8n mode — n8n-autopilot only where n8n work happens

Run, with the argument the user gave (default `on`):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/n8n-mode.sh" <on|off|status> "${CLAUDE_SESSION_ID}"
```

Show the output. With `on` it also runs the SessionStart probes once — follow any
`AUTOPILOT_ACTION_REQUIRED:` line exactly as CLAUDE.md "Auto-Reactions on SessionStart" says.

## How the mode works

| Repo / session | Probes at session start | Feedback Stop gate + capture | Safety gates on n8nac commands |
|---|---|---|---|
| always-on repo | yes | yes | yes |
| other repo, mode off | no (one hint line if the repo contains n8n files) | no | yes |
| other repo, mode on (this skill or first `n8nac` command) | once, when switched on via this skill | yes | yes |

**Always-on** (dedicated n8n repos) — any of:
- `N8N_AUTOPILOT_MODE=always` in the `env` block of `.claude/settings.json`
- `.n8n-autopilot/mode` containing the line `always`
- `n8nac-config.json` in the project root

`N8N_AUTOPILOT_MODE=off` keeps the mode off, even after an n8nac command.

The first `n8nac` command of a session switches the mode on automatically (silent, no probes). Run
this skill instead when you want the setup/drift probes before you start.
