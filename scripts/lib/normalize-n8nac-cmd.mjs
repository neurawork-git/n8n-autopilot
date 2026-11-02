#!/usr/bin/env node
// normalize-n8nac-cmd.mjs — bring an n8nac shell command into the one shape the gates match on.
//
// The gates (enforce-env, push-gate, push-lint-gate) look for `n8nac <subcommand>` and resolve
// files relative to $PWD. Three common forms slipped past them:
//   npx -y n8nac@2.7.0 push x.ts     version pin  → `n8nac@2.7.0 push` never matched `n8nac push`
//   npx n8nac --env e push x.ts      global flag  → `--env e` sits between n8nac and the subcommand
//   cd n8n && npx n8nac push x.ts    monorepo     → push-gate resolved x.ts from the session root
// Output: three NUL-terminated fields — cmd, env, cd (commands may span lines, so no newline split)
//   cmd — command with `@<version>` dropped, a leading `cd <dir> &&|;` removed, and a global
//         `--env <e>` turned into an inline `N8NAC_ENVIRONMENT=<e>` (enforce-env accepts it)
//   env — the env the command names (inline var or --env), "" if none
//   cd  — the leading cd target, "" if none (the caller runs the gates from there)
// Usage: node normalize-n8nac-cmd.mjs "<command>"
const raw = String(process.argv[2] || "");
let cmd = raw;
let cd = "";
const unq = (s) => s.replace(/^(["'])(.*)\1$/, "$2");

const lead = cmd.match(/^\s*cd\s+("[^"]+"|'[^']+'|[^\s;&|]+)\s*(?:&&|;)\s*/);
if (lead) { cd = unq(lead[1]); cmd = cmd.slice(lead[0].length); }

cmd = cmd.replace(/\bn8nac@[^\s;&|]+/g, "n8nac");

let env = "";
const inline = cmd.match(/(?:^|[\s;&|(])N8NAC_ENVIRONMENT=("[^"]*"|'[^']*'|[^\s;&|]+)/);
if (inline) env = unq(inline[1]);
const flag = cmd.match(/\bn8nac\s+--env(?:=|\s+)("[^"]*"|'[^']*'|[^\s;&|]+)\s*/);
if (flag) {
  env = env || unq(flag[1]);
  cmd = cmd.replace(flag[0], "n8nac ");
  if (!inline) cmd = cmd.replace(/\b(npx\s+(?:-y\s+|--yes\s+)?)?n8nac /, (m) => `N8NAC_ENVIRONMENT=${unq(flag[1])} ${m}`);
}
process.stdout.write(`${cmd}\0${env}\0${cd}\0`);
