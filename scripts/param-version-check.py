#!/usr/bin/env python3
"""param-version-check.py — are the parameters of every node valid for the node's typeVersion?

n8n gates parameters per version through `displayOptions.show/hide['@version']`. A key that exists
only for another version is ACCEPTED by `n8nac skills validate` (it checks the name, not the gate)
and then SILENTLY IGNORED by n8n — formTrigger 2.5 with a top-level `path` registered the form under
its webhookId and answered 500 (#94); the Anthropic chat model's `model` changed shape at 1.3 and
validation kept checking the old one (#84). This script reads the version-gated schema from
`npx n8nac skills node-info <type> --json` and evaluates the gate for the version the node uses.

Usage:
  python param-version-check.py <compiled-workflow.json> [--json]
  python param-version-check.py --selftest

Exit: 0 = pass · 1 = a parameter is not valid for its node's typeVersion · 2 = cannot check
(n8nac missing). Types node-info does not know (community nodes, hidden core nodes) are reported as
`unknown` warnings — instance-node-check.mjs judges those.

Only TOP-LEVEL parameter keys are evaluated. Nested collections vary too much per node to gate
deterministically; the validator covers their names. A key that appears in NO version is a warning
(the validator's job), a key that appears only in OTHER versions is a blocker (this script's job).
"""
import json
import os
import subprocess
import sys
import time

STICKY = "n8n-nodes-base.stickynote"
CACHE_TTL = 24 * 3600


def cache_dir():
    d = os.path.join(os.environ.get("TMPDIR") or os.environ.get("TEMP") or "/tmp", "n8n-autopilot-node-info")
    os.makedirs(d, exist_ok=True)
    return d


def _cache_path(ntype):
    return os.path.join(cache_dir(), ntype.replace("/", "_").replace("@", "") + ".json")


def _cached(ntype):
    p = _cache_path(ntype)
    if os.path.exists(p) and time.time() - os.path.getmtime(p) < CACHE_TTL:
        try:
            with open(p, encoding="utf-8") as f:
                return json.load(f)
        except ValueError:
            pass
    return None


def _store(ntype, info):
    with open(_cache_path(ntype), "w", encoding="utf-8") as f:
        json.dump(info, f)


def fetch_node_infos(types):
    """Version-gated schemas for all `types` — ONE n8nac process for every uncached type
    (scripts/node-schemas.mjs on n8nac's NodeSchemaProvider; an npx start costs ~7 s on Windows,
    per-type node-info calls made one push take 20 s+). Cached 24 h per type.
    Returns {type: info | None}; None = n8nac does not know the type."""
    out = {}
    todo = []
    for t in types:
        c = _cached(t)
        if c is not None:
            out[t] = None if c.get("__missing__") else c
        else:
            todo.append(t)
    if todo:
        helper = os.path.join(os.path.dirname(os.path.abspath(__file__)), "node-schemas.mjs")
        cmd = ["npx", "--yes", "-p", "n8nac", "node", helper, *todo]
        try:
            r = subprocess.run(subprocess.list2cmdline(cmd) if os.name == "nt" else cmd, shell=(os.name == "nt"), capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180)
        except (OSError, subprocess.TimeoutExpired) as e:
            raise RuntimeError(f"n8nac node-schemas failed: {e}")
        raw = r.stdout or ""
        i = raw.find("{")
        try:
            results = json.loads(raw[i:]) if i >= 0 else None
        except ValueError:
            results = None
        if not isinstance(results, dict):
            raise RuntimeError(f"node-schemas.mjs returned no usable output (exit {r.returncode}): {(r.stderr or raw)[:200]}")
        for t in todo:
            doc = results.get(t)
            if not doc or not (doc.get("schema") or {}).get("properties"):
                _store(t, {"__missing__": True})
                out[t] = None
            else:
                _store(t, doc)
                out[t] = doc
    return out


def node_info(ntype):
    return fetch_node_infos([ntype])[ntype]


def _num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def cond_matches(cond, v):
    """One entry of a `@version` list: a plain version number or {"_cnd": {...}}."""
    n = _num(cond)
    if n is not None:
        return abs(n - v) < 1e-9
    if isinstance(cond, dict) and isinstance(cond.get("_cnd"), dict):
        for op, arg in cond["_cnd"].items():
            a = _num(arg)
            if op == "eq" and a is not None and abs(a - v) >= 1e-9:
                return False
            if op == "not" and a is not None and abs(a - v) < 1e-9:
                return False
            if op == "gte" and a is not None and v < a - 1e-9:
                return False
            if op == "gt" and a is not None and v <= a + 1e-9:
                return False
            if op == "lte" and a is not None and v > a + 1e-9:
                return False
            if op == "lt" and a is not None and v >= a - 1e-9:
                return False
            if op == "between" and isinstance(arg, dict):
                lo, hi = _num(arg.get("from")), _num(arg.get("to"))
                if (lo is not None and v < lo - 1e-9) or (hi is not None and v > hi + 1e-9):
                    return False
        return True
    return True  # unknown condition shape → do not block on it


def prop_admits(prop, v):
    """Does this property exist for typeVersion v (only the @version dimension is evaluated)?"""
    do = prop.get("displayOptions") or {}
    show = (do.get("show") or {}).get("@version")
    hide = (do.get("hide") or {}).get("@version")
    if show and not any(cond_matches(c, v) for c in show):
        return False
    if hide and any(cond_matches(c, v) for c in hide):
        return False
    return True


def describe_versions(props, v_all):
    ok = [x for x in v_all if any(prop_admits(p, x) for p in props)]
    return ", ".join(f"{x:g}" for x in ok) if ok else "none"


def check(wf, lookup=None):
    blockers, warnings, unknown = [], [], []
    active = [n for n in (wf.get("nodes") or []) if not n.get("disabled") and (n.get("type") or "").lower() != STICKY]
    types = sorted({n.get("type") or "" for n in active})
    seen = {t: lookup(t) for t in types} if lookup else fetch_node_infos(types)
    for n in active:
        t = n.get("type") or ""
        info = seen[t]
        if info is None:
            if t not in unknown:
                unknown.append(t)
            continue
        v = _num(n.get("typeVersion")) or 1.0
        v_all = [x for x in (_num(x) for x in (info.get("version") if isinstance(info.get("version"), list) else [info.get("version")])) if x is not None]
        props = (info.get("schema") or {}).get("properties") or []
        by_name = {}
        for p in props:
            by_name.setdefault(p.get("name"), []).append(p)
        for key in (n.get("parameters") or {}).keys():
            cands = by_name.get(key)
            if not cands:
                warnings.append({"node": n.get("name"), "type": t, "version": v, "param": key, "msg": "not a parameter of this node in any version (validator territory)"})
                continue
            if not any(prop_admits(p, v) for p in cands):
                blockers.append({"node": n.get("name"), "type": t, "version": v, "param": key, "msg": f"parameter '{key}' does not exist for typeVersion {v:g} (exists in: {describe_versions(cands, v_all)}) — n8n ignores it silently"})
    for t in unknown:
        warnings.append({"node": None, "type": t, "version": None, "param": None, "msg": "node-info does not know this type — instance-node-check judges it"})
    return blockers, warnings


def selftest():
    form = {"version": [1, 2, 2.1, 2.2, 2.5], "schema": {"properties": [
        {"name": "path", "displayOptions": {"show": {"@version": [{"_cnd": {"lte": 2.1}}]}}},
        {"name": "responseMode", "displayOptions": {"show": {"@version": [1, 2, 2.1]}}},
        {"name": "responseMode", "displayOptions": {"show": {"@version": [{"_cnd": {"gte": 2.2}}]}}},
        {"name": "options"},
        {"name": "legacy", "displayOptions": {"hide": {"@version": [{"_cnd": {"gte": 2}}]}}},
    ]}}
    lookup = lambda t: form if t == "n8n-nodes-base.formTrigger" else None
    wf = {"nodes": [
        {"name": "F", "type": "n8n-nodes-base.formTrigger", "typeVersion": 2.5, "parameters": {"path": "x", "responseMode": "lastNode", "options": {}, "legacy": 1, "bogus": 1}},
        {"name": "Old", "type": "n8n-nodes-base.formTrigger", "typeVersion": 2, "parameters": {"path": "x", "legacy": 1}},
        {"name": "C", "type": "n8n-nodes-community.thing", "typeVersion": 1, "parameters": {"a": 1}},
        {"name": "S", "type": "n8n-nodes-base.stickyNote", "typeVersion": 1, "parameters": {"content": "x"}},
    ]}
    b, w = check(wf, lookup)
    assert [(x["node"], x["param"]) for x in b] == [("F", "path"), ("F", "legacy"), ("Old", "legacy")], b
    assert "exists in: 1, 2, 2.1" in b[0]["msg"], b[0]
    assert "exists in: 1)" in b[2]["msg"], b[2]
    assert [(x["node"], x["param"]) for x in w if x["param"]] == [("F", "bogus")], w
    assert [x["type"] for x in w if not x["param"]] == ["n8n-nodes-community.thing"], w
    print("param-version-check selftest: ok")


def main(argv):
    if "--selftest" in argv:
        selftest()
        return 0
    args = [a for a in argv if not a.startswith("--")]
    if not args:
        print(__doc__)
        return 2
    try:
        with open(args[0], encoding="utf-8") as f:
            wf = json.load(f)
    except (OSError, ValueError) as e:
        print(f"param-version-check: cannot read {args[0]}: {e}", file=sys.stderr)
        return 2
    try:
        blockers, warnings = check(wf)
    except RuntimeError as e:
        print(json.dumps({"ok": False, "error": str(e)}) if "--json" in argv else f"param-version-check: {e}", file=sys.stderr)
        return 2
    if "--json" in argv:
        print(json.dumps({"ok": not blockers, "blockers": blockers, "warnings": warnings}, indent=2))
    else:
        for x in blockers:
            print(f"BLOCK  param-version     {x['node']:<30} {x['msg']}")
        for x in warnings:
            print(f"warn   param-version     {x['node'] or x['type']:<30} {x['msg']}")
        print(f"param-version-check: {'PASS' if not blockers else 'FAIL'} — {len(blockers)} blocker(s), {len(warnings)} warning(s)")
    return 0 if not blockers else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
