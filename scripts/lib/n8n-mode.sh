#!/usr/bin/env bash
# n8n-mode.sh (lib) — per-session n8n mode. Sourced by the hooks and by scripts/n8n-mode.sh.
#
# The heavy, context-adding hooks (SessionStart probes, Stop feedback gate, feedback capture) run
# only while the mode is on. Project monorepos carry an n8n/ subfolder next to everything else, so
# "the repo contains workflows" is no longer a reason to load n8n into every session there.
#
# The mode is on when
#   - the repo is a dedicated n8n repo (always on):
#       N8N_AUTOPILOT_MODE=always  (env block of a settings.json)
#       .n8n-autopilot/mode containing `always`
#       n8nac-config.json in the project root (n8nac workspace root)
#   - or this session switched it on: /n8n-autopilot:n8n-mode, or automatically with the first
#     n8nac command (pretooluse-gate.sh).
# N8N_AUTOPILOT_MODE=off keeps it off, even for the first n8nac command.
#
# The safety gates on n8nac commands (curl-block, enforce-env, push-gate, push-lint-gate) do NOT
# depend on the mode — they fire on the command itself.
#
# Session markers live under $HOME, not $TMPDIR: hooks and the Bash tool may see different TMPDIRs.

N8N_MODE_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
N8N_MODE_DIR="${N8N_AUTOPILOT_STATE_DIR:-$HOME/.cache/n8n-autopilot/sessions}"

n8n_mode_sid() { printf '%s' "${1:-}" | tr -cd 'A-Za-z0-9_-'; }

n8n_mode_always() {
  [ "${N8N_AUTOPILOT_MODE:-}" = "always" ] && return 0
  [ "${N8N_AUTOPILOT_MODE:-}" = "off" ] && return 1
  [ -f "$N8N_MODE_ROOT/.n8n-autopilot/mode" ] && grep -qx '[[:space:]]*always[[:space:]]*' "$N8N_MODE_ROOT/.n8n-autopilot/mode" 2>/dev/null && return 0
  [ -f "$N8N_MODE_ROOT/n8nac-config.json" ] && return 0
  return 1
}

n8n_mode_session_on() {
  local sid; sid="$(n8n_mode_sid "${1:-}")"
  [ -n "$sid" ] && [ -f "$N8N_MODE_DIR/$sid" ]
}

n8n_mode_active() {
  [ "${N8N_AUTOPILOT_MODE:-}" = "off" ] && return 1
  n8n_mode_always || n8n_mode_session_on "${1:-}"
}

# n8n_mode_enable <session_id> <reason> — idempotent; prunes markers older than 14 days.
n8n_mode_enable() {
  local sid; sid="$(n8n_mode_sid "${1:-}")"
  [ -n "$sid" ] || return 1
  mkdir -p "$N8N_MODE_DIR" 2>/dev/null || return 1
  [ -f "$N8N_MODE_DIR/$sid" ] || printf '%s\n' "${2:-manual}" > "$N8N_MODE_DIR/$sid"
  find "$N8N_MODE_DIR" -type f -mtime +14 -delete 2>/dev/null || true
}

n8n_mode_disable() {
  local sid; sid="$(n8n_mode_sid "${1:-}")"
  [ -n "$sid" ] && rm -f "$N8N_MODE_DIR/$sid"
}
