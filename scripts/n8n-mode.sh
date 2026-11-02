#!/usr/bin/env bash
# n8n-mode.sh — switch the per-session n8n mode and gate the heavy hooks on it.
# Mechanism + rules: scripts/lib/n8n-mode.sh.
#
#   n8n-mode.sh on <session_id>      switch on for this session, then run the SessionStart probes once
#   n8n-mode.sh off <session_id>     switch off for this session (safety gates stay active)
#   n8n-mode.sh status <session_id>  report the mode and why
#   n8n-mode.sh guard                exit 0 only in an always-on repo (chained before SessionStart probes)
#   n8n-mode.sh hint                 SessionStart: one line in repos that touch n8n but are not always-on
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/n8n-mode.sh
. "$HERE/lib/n8n-mode.sh"

run_probes() {
  bash "$HERE/report-session-env.sh" </dev/null 2>&1 || true
  bash "$HERE/setup-check.sh" </dev/null 2>&1 || true
  bash "$HERE/check-schema-versions.sh" --quiet </dev/null 2>&1 || true
  bash "$HERE/check-credential-freshness.sh" --quiet </dev/null 2>&1 || true
  bash "$HERE/check-mirror-drift.sh" --quiet </dev/null 2>&1 || true
  bash "$HERE/check-workspace-migration.sh" --quiet </dev/null 2>&1 || true
  bash "$HERE/check-custom-nodes-resolution.sh" --quiet </dev/null 2>&1 || true
  bash "$HERE/check-instance-cache.sh" --quiet </dev/null 2>&1 || true
  node "$HERE/check-native-mcp.mjs" --quiet </dev/null 2>&1 || true
  bash "$HERE/check-feedback-pending.sh" --quiet </dev/null 2>&1 || true
  bash "$HERE/check-plugin-version.sh" </dev/null 2>&1 || true
}

ACTION="${1:-status}"
SID="${2:-}"

case "$ACTION" in
  guard)
    n8n_mode_always
    ;;
  hint)
    n8n_mode_always && exit 0
    [ "${N8N_AUTOPILOT_MODE:-}" = "off" ] && exit 0
    bash "$HERE/lib/n8n-repo-guard.sh" || exit 0
    echo "n8n-autopilot: n8n mode is off in this session (repo is not always-on). It switches on with the first n8nac command, or run /n8n-autopilot:n8n-mode before n8n work to also load the setup/drift probes."
    ;;
  on)
    if [ "${N8N_AUTOPILOT_MODE:-}" = "off" ]; then
      echo "n8n mode stays off: N8N_AUTOPILOT_MODE=off is set (settings.json env block). The safety gates on n8nac commands still apply."
      exit 1
    fi
    if n8n_mode_always; then
      echo "n8n mode: always on in this repo (probes already ran at session start)."
    else
      [ -n "$(n8n_mode_sid "$SID")" ] || { echo "ERROR: no session id — call via /n8n-autopilot:n8n-mode." >&2; exit 1; }
      n8n_mode_enable "$SID" manual || { echo "ERROR: could not write session marker under $N8N_MODE_DIR" >&2; exit 1; }
      echo "n8n mode: ON for this session. Running the n8n probes once:"
    fi
    run_probes
    ;;
  off)
    if n8n_mode_always; then
      echo "n8n mode: this repo is always-on (N8N_AUTOPILOT_MODE=always, .n8n-autopilot/mode or root n8nac-config.json) — remove that to make it per-session."
      exit 0
    fi
    n8n_mode_disable "$SID"
    echo "n8n mode: OFF for this session. The next n8nac command switches it on again; set N8N_AUTOPILOT_MODE=off to prevent that."
    ;;
  status)
    if [ "${N8N_AUTOPILOT_MODE:-}" = "off" ]; then
      echo "n8n mode: OFF (N8N_AUTOPILOT_MODE=off)"
    elif n8n_mode_always; then
      echo "n8n mode: ON — always-on repo"
    elif n8n_mode_session_on "$SID"; then
      echo "n8n mode: ON — this session ($(cat "$N8N_MODE_DIR/$(n8n_mode_sid "$SID")" 2>/dev/null))"
    else
      echo "n8n mode: OFF — switches on with the first n8nac command or /n8n-autopilot:n8n-mode"
    fi
    ;;
  *)
    echo "usage: n8n-mode.sh on|off|status <session_id> | guard | hint" >&2
    exit 2
    ;;
esac
