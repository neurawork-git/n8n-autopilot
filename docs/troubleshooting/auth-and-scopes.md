# Auth, API-key scopes, and per-environment credentials

Failures that look like a broken key or a broken instance, and are neither. Each one below cost real
debugging time before it was understood — the common thread is an error message that points at the
wrong thing.

---

## `403 Forbidden` on ONE endpoint while everything else works

**Symptom.** `npx n8nac credential list --json` returns HTTP 403, while the *same* API key reads,
pushes and activates workflows without complaint. `find-credential`, `sync-credentials` and
`workflow credential-required` all fail with it.

**It is not a bad key.** n8n's public API authorises each endpoint against the API key's **own**
scopes — the `scopes` column of the `user_api_keys` row. Despite its name,
`apiKeyHasScopeWithGlobalScopeFallback()` has **no fallback to the user's global role**: a
`global:admin` still gets `403` if the key itself lacks `credential:list`. n8n API-key JWTs carry no
scope claims at all, so nothing in the token can compensate.

**And it cannot be repaired in place.** n8n **never backfills new scopes onto an existing key**. A key
created before a scope existed can never acquire it — re-pasting or re-copying the same key changes
nothing, which is exactly the loop the old generic error message invited.

**Fix**

```bash
# 1. Create a NEW API key in the n8n UI with the credential scopes enabled.
# 2. Store it for the environment:
npx n8nac env auth set <env> --api-key-stdin
```

**Workaround for a single credential ID**, without the endpoint: open the credential in the n8n UI —
the ID is the last path segment of the URL, `/home/credentials/<id>`.

Both `sync-credentials` and `find-credential` now detect the 403 and print this instead of a generic
failure.

---

## Every environment needs `env auth set` — even when they share one instance target

**Symptom.** A workspace with a dozen environments all pointing at the *same* instance target: the
authenticated one works, every other one fails asking for a host and API key. It reads like the key
broke, or like the environment is misconfigured.

**Cause.** Auth is stored **per environment**, not per instance target. Sharing a target does not
share credentials, and nothing in the CLI output says so.

**Fix.** Run `env auth set` once per environment, with the same key:

```bash
for e in dev staging prod; do
  npx n8nac env auth set "$e" --api-key-stdin < key.txt
done
```

`npx n8nac env list --json` shows each environment's `apiKeySource` / `apiKeyAvailable` — use it to
see which ones are still unauthenticated, rather than discovering it one failed command at a time.

---

## Activation fails with no reason given

**Symptom.** `npx n8nac workflow activate <id>` reports only `did not report active=true` and exits 1.
The cause n8n actually returned (the node issue list) is not passed through, so it is tempting to
blame the publish model or the instance.

**Do not guess — the workflow is broken** (see the hard rule in `CLAUDE.md`). Get the real reason:

1. **Check the node issues directly** — `npx n8nac workflow present <id> --json` gives the UI URL;
   opening it shows the offending node with its issue marker.
2. **Most common cause by far:** a node calling an external service with no `credentials:` block. Note
   that one foreign credential fails the *whole* workflow before the first node runs.
3. **Referenced sub-workflow named in the error** → this is publish **order**, not a defect: callees
   must be published/active before their caller. Fix the order, do not "fix" the file.
4. **Cross-check the instance** with a known-good trivial workflow before suspecting n8n itself.

Passing the node-issue list through belongs in n8nac; until it does, the steps above are the route to
the cause.
