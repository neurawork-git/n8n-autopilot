#!/bin/bash
# report-session-env.sh — SessionStart: state which n8n env (instance + project)
# this session targets, up front. One env per session is the normal rule.
#
# Resolution order:
#   1. $N8NAC_ENVIRONMENT (session default, e.g. from .claude/settings.json env block)
#   2. else the GLOBAL active env (`env use`) — flagged as a shared fallback to fix.
#
# Called by: hooks/hooks.json SessionStart.

LIST=$(npx --yes n8nac env list --json 2>/dev/null)
if [ -z "$LIST" ]; then
  exit 0   # n8nac not set up yet — other hooks report that
fi

printf "%s" "$LIST" | TARGET="$N8NAC_ENVIRONMENT" node -e "
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
  try {
    const i=d.indexOf('{'); const j=JSON.parse(d.slice(i));
    const envs=j.environments||[];
    const target=(process.env.TARGET||'').trim();
    let e, pinned;
    if (target) { e=envs.find(x=>x.name===target||x.id===target); pinned=true; }
    if (!e) { e=envs.find(x=>x.id===j.activeEnvironmentId); pinned=false; }
    if (!e) { console.log('n8n session env: UNRESOLVED (set N8NAC_ENVIRONMENT).'); return; }
    const host=(e.resolved&&e.resolved.host)||e.environmentTargetId||'?';
    const proj=e.projectName||'(default project)';
    console.log('=== n8n session env ===');
    console.log('  env:     '+e.name+(pinned?'  (session default — N8NAC_ENVIRONMENT)':'  (GLOBAL active fallback — no session env set)'));
    console.log('  host:    '+host);
    console.log('  project: '+proj);
    if (!pinned) {
      console.log('');
      console.log('  ⚠️  No per-session env. n8nac uses the SHARED global active env —');
      console.log('     wrong when other sessions target other projects. Set a default:');
      console.log('     add  \"env\": { \"N8NAC_ENVIRONMENT\": \"<env-name>\" }  to .claude/settings.json');
    }
  } catch(e){ /* silent */ }
});" 2>/dev/null
exit 0
