#!/usr/bin/env python3
"""lint-workflow.py — deterministic design-quality gate for a COMPILED n8n workflow (JSON).

The LLM reviewer (workflow-reviewer) describes these rules in prose and runs inside `safe()`,
so a crashed reviewer opens the gate. This script is the part of the checklist that can be
decided by code, and it runs as a PreToolUse hook before every `n8nac push` (push-lint-gate.sh).

Usage:
  python lint-workflow.py <workflow.json> [--json]
  python lint-workflow.py --selftest

Exit: 0 = pass (warnings allowed) · 1 = blockers · 2 = usage / unreadable input.

Rules (B = blocker, W = warning):
  B empty-compile     compiled JSON has 0 nodes (transformer dropped the class, #20)
  B no-trigger        no trigger node at all
  B dead-trigger      trigger with no outgoing edge
  B orphan            non-trigger node with no incoming edge and not an AI sub-node (#93)
  B masked-error      continueOnFail / onError=continueRegularOutput without a downstream error
                      check: the failed item flows on as a success — an If/Switch/Filter/Code
                      successor must test the error field (feedback: executeWorkflow/Postgres with
                      continueRegularOutput reported success for failed steps). `notes` alone no
                      longer exempts (it did until 5.5.0).
  B error-unwired     onError=continueErrorOutput but the error output has no edge (the `.error()`
                      edge n8nac emits is a silent no-op, #57)
  B no-error-strategy a TOP-LEVEL workflow (trigger is not executeWorkflowTrigger/errorTrigger)
                      calls external services but has neither settings.errorWorkflow nor a wired
                      error output — a failure vanishes into the execution list
  B expression        unbalanced {{ }} or unbalanced brackets inside an expression (#92)
  B empty-code        Code node without jsCode / pythonCode
  B no-respond        webhook responseMode=responseNode without a respondToWebhook node
  B not-mcp-testable  settings.availableInMCP is not true — the native MCP test path cannot execute it
  W retry-missing     httpRequest without retryOnFail — one transient 5xx fails the run (#88)
  W code-env-access   Code node reads $env or require()s a builtin — hardened instances deny both
                      (N8N_BLOCK_ENV_ACCESS_IN_NODE, NODE_FUNCTION_ALLOW_BUILTIN), found at runtime (#97)
  W code-heavy        Code nodes > 50 % of functional nodes (#76)
  W no-sticky         no stickyNote documenting the workflow
  W overlap           two nodes closer than 80 px on both axes

typeVersion and parameter names are NOT checked here: push-lint-gate.sh asks the running instance
(`instance-node-check.mjs`, get_node_types) and the version-gated schema (`param-version-check.py`).
"""
import json
import os
import re
import sys

STICKY = "n8n-nodes-base.stickynote"
CODE = "n8n-nodes-base.code"
RESPOND = "n8n-nodes-base.respondtowebhook"
HTTP = "n8n-nodes-base.httprequest"
SUB_TRIGGERS = ("n8n-nodes-base.executeworkflowtrigger", "n8n-nodes-base.errortrigger")
ERROR_CHECKERS = ("n8n-nodes-base.if", "n8n-nodes-base.switch", "n8n-nodes-base.filter", CODE)


def is_trigger(node):
    t = node["type"].lower()
    return t.endswith("trigger") or t.endswith(".webhook")  # n8n-nodes-base.form is a form PAGE, not a trigger


def is_external(node):
    """Calls something outside this n8n run: an HTTP request or any credentialed node."""
    return node["type"].lower() == HTTP or bool(node.get("credentials"))


def walk_strings(value, path=""):
    if isinstance(value, str):
        yield path, value
    elif isinstance(value, dict):
        for k, v in value.items():
            yield from walk_strings(v, f"{path}.{k}" if path else k)
    elif isinstance(value, list):
        for i, v in enumerate(value):
            yield from walk_strings(v, f"{path}[{i}]")


def brackets_balanced(expr):
    """Balance of () [] {} inside one expression body; string literals are skipped."""
    pairs = {")": "(", "]": "[", "}": "{"}
    stack, quote, i = [], None, 0
    while i < len(expr):
        c = expr[i]
        if quote:
            if c == "\\":
                i += 1
            elif c == quote:
                quote = None
        elif c in "'\"`":
            quote = c
        elif c in "([{":
            stack.append(c)
        elif c in ")]}":
            if not stack or stack[-1] != pairs[c]:
                return False
            stack.pop()
        i += 1
    return not stack and quote is None


def check_expression(s):
    """Returns a problem string or None for a parameter value that carries expressions."""
    if not s.startswith("=") or ("{{" not in s and "}}" not in s):
        return None  # only `=`-prefixed strings are expressions; JSON schemas legitimately end in `}}`
    if s.count("{{") != s.count("}}"):
        return f"unbalanced {{{{ }}}} ({s.count('{{')} open / {s.count('}}')} close)"
    for body in re.findall(r"\{\{(.*?)\}\}", s, flags=re.S):
        if not brackets_balanced(body):
            return f"unbalanced brackets in {{{{ {body.strip()[:60]} }}}}"
    return None


def lint(wf):
    blockers, warnings = [], []
    B = lambda rule, node, msg: blockers.append({"rule": rule, "node": node, "msg": msg})
    W = lambda rule, node, msg: warnings.append({"rule": rule, "node": node, "msg": msg})

    nodes = wf.get("nodes") or []
    conns = wf.get("connections") or {}
    by_name = {n["name"]: n for n in nodes}

    incoming, outgoing, main_succ, ai_source, error_wired = {}, {}, {}, set(), set()
    for src, outs in conns.items():
        for out_type, lanes in (outs or {}).items():
            for lane_idx, lane in enumerate(lanes or []):
                for edge in lane or []:
                    dst = edge.get("node")
                    outgoing.setdefault(src, set()).add(dst)
                    incoming.setdefault(dst, set()).add(src)
                    if out_type != "main":
                        ai_source.add(src)
                    if out_type == "main":
                        main_succ.setdefault(src, set()).add(dst)
                        if lane_idx == len(lanes) - 1 and len(lanes) > 1:
                            error_wired.add(src)

    functional = [n for n in nodes if n["type"].lower() != STICKY and not n.get("disabled")]
    if not nodes:
        B("empty-compile", None, "compiled workflow has 0 nodes — the transformer dropped the class (#20: non-ASCII class identifier?)")
        return blockers, warnings
    triggers = [n for n in functional if is_trigger(n)]
    if not triggers:
        B("no-trigger", None, "workflow has no trigger node")

    def checks_error(succ_name):
        s = by_name.get(succ_name)
        if not s or s["type"].lower() not in ERROR_CHECKERS:
            return False
        return "error" in json.dumps(s.get("parameters") or {}).lower()

    has_error_branch = False
    for n in functional:
        name, t = n["name"], n["type"].lower()
        if is_trigger(n):
            if not outgoing.get(name):
                B("dead-trigger", name, "trigger has no outgoing edge")
        elif not incoming.get(name) and name not in ai_source:
            B("orphan", name, "no incoming edge and not an AI sub-node — n8n never executes it")

        if n.get("continueOnFail") is True or n.get("onError") == "continueRegularOutput":
            if not any(checks_error(s) for s in main_succ.get(name, ())):
                B("masked-error", name, "continueOnFail/continueRegularOutput without a downstream error check — the failed item flows on as a success. Wire the main output into an If/Switch/Filter (or Code) that tests $json.error, or use onError: continueErrorOutput with an error branch")
        if n.get("onError") == "continueErrorOutput":
            if name not in error_wired:
                B("error-unwired", name, "onError=continueErrorOutput but the error output has no edge")
            else:
                has_error_branch = True

        if t == CODE:
            p = n.get("parameters") or {}
            body = str(p.get("jsCode") or p.get("pythonCode") or "")
            if not body.strip():
                B("empty-code", name, "Code node without jsCode/pythonCode")
            elif re.search(r"\$env\b|\brequire\s*\(|\bimport\s*\(", body):
                W("code-env-access", name, "Code node reads $env or loads a module — hardened instances deny both at runtime (N8N_BLOCK_ENV_ACCESS_IN_NODE / NODE_FUNCTION_ALLOW_BUILTIN); prefer credentials + native nodes (#97)")

        if t == HTTP and not n.get("retryOnFail"):
            W("retry-missing", name, "httpRequest without retryOnFail — a single transient 5xx fails the run; set retryOnFail + maxTries + waitBetweenTries")

        for path, s in walk_strings(n.get("parameters") or {}):
            if t == CODE and path in ("jsCode", "pythonCode"):
                continue  # ponytail: JS/Python bodies are not expressions; a bracket scan there false-positives on regex/comments
            prob = check_expression(s)
            if prob:
                B("expression", name, f"{path}: {prob}")

        if t == "n8n-nodes-base.webhook" and (n.get("parameters") or {}).get("responseMode") == "responseNode":
            if not any(m["type"].lower() == RESPOND for m in functional):
                B("no-respond", name, "responseMode=responseNode but no respondToWebhook node")

    settings = wf.get("settings") or {}
    if settings.get("availableInMCP") is not True:
        B("not-mcp-testable", None, "settings.availableInMCP must be true — the pipeline tests through the native n8n MCP (execute_workflow)")

    top_level = triggers and not all(n["type"].lower() in SUB_TRIGGERS for n in triggers)
    external = [n["name"] for n in functional if is_external(n) and not is_trigger(n)]
    if top_level and external and not str(settings.get("errorWorkflow") or "").strip() and not has_error_branch:
        B("no-error-strategy", None, f"top-level workflow calls external services ({', '.join(external[:4])}{'…' if len(external) > 4 else ''}) but has no error strategy — set settings.errorWorkflow to the instance's error-handler workflow (grep .n8n-autopilot/instance-cache.json for errorTrigger) or wire an error output (onError: continueErrorOutput → error branch)")

    code_nodes = [n for n in functional if n["type"].lower() == CODE]
    if functional and len(code_nodes) / len(functional) > 0.5:
        W("code-heavy", None, f"{len(code_nodes)}/{len(functional)} functional nodes are Code nodes — prefer if/switch/set/filter")
    if not any(n["type"].lower() == STICKY for n in nodes):
        W("no-sticky", None, "no stickyNote documents purpose + credentials")
    pos = [(n["name"], n.get("position") or [0, 0]) for n in nodes]
    for i in range(len(pos)):
        for j in range(i + 1, len(pos)):
            (a, pa), (b, pb) = pos[i], pos[j]
            if abs(pa[0] - pb[0]) < 80 and abs(pa[1] - pb[1]) < 80:
                W("overlap", a, f"overlaps '{b}' on the canvas")
    return blockers, warnings


def selftest():
    good = {
        "settings": {"availableInMCP": True, "errorWorkflow": "ErrHandler01"},
        "nodes": [
            {"name": "Note", "type": "n8n-nodes-base.stickyNote", "typeVersion": 1, "position": [0, 0], "parameters": {"content": "x"}},
            {"name": "Hook", "type": "n8n-nodes-base.webhook", "typeVersion": 2, "position": [200, 0], "parameters": {"responseMode": "responseNode"}},
            {"name": "Set", "type": "n8n-nodes-base.set", "typeVersion": 3.4, "position": [400, 0], "parameters": {"v": "={{ $json.a.map(x => x[0]) }}", "schema": "{\"a\":{\"b\":{}}}"}},
            {"name": "Call", "type": "n8n-nodes-base.httpRequest", "typeVersion": 4.2, "retryOnFail": True, "position": [600, 200], "parameters": {"url": "https://x"}},
            {"name": "Respond", "type": "n8n-nodes-base.respondToWebhook", "typeVersion": 1.1, "position": [600, 0], "parameters": {}},
            {"name": "Model", "type": "@n8n/n8n-nodes-langchain.lmChatOpenAi", "typeVersion": 1, "position": [400, 200], "parameters": {}},
            {"name": "Agent", "type": "@n8n/n8n-nodes-langchain.agent", "typeVersion": 1.7, "position": [800, 0], "parameters": {}},
        ],
        "connections": {
            "Hook": {"main": [[{"node": "Set", "type": "main", "index": 0}]]},
            "Set": {"main": [[{"node": "Call", "type": "main", "index": 0}]]},
            "Call": {"main": [[{"node": "Respond", "type": "main", "index": 0}]]},
            "Respond": {"main": [[{"node": "Agent", "type": "main", "index": 0}]]},
            "Model": {"ai_languageModel": [[{"node": "Agent", "type": "ai_languageModel", "index": 0}]]},
        },
    }
    b, w = lint(good)
    assert b == [], b
    assert [x["rule"] for x in w] == [], w

    # continueRegularOutput is fine when the successor checks the error field
    checked = json.loads(json.dumps(good))
    checked["nodes"][3]["onError"] = "continueRegularOutput"
    checked["nodes"].append({"name": "Failed?", "type": "n8n-nodes-base.if", "typeVersion": 2.2, "position": [800, 200], "parameters": {"conditions": {"leftValue": "={{ $json.error }}"}}})
    checked["connections"]["Call"] = {"main": [[{"node": "Failed?", "type": "main", "index": 0}]]}
    checked["connections"]["Failed?"] = {"main": [[{"node": "Respond", "type": "main", "index": 0}]]}
    assert lint(checked)[0] == [], lint(checked)[0]

    # an error branch replaces settings.errorWorkflow as the strategy
    branch = json.loads(json.dumps(good))
    del branch["settings"]["errorWorkflow"]
    branch["nodes"][3]["onError"] = "continueErrorOutput"
    branch["nodes"].append({"name": "Stop", "type": "n8n-nodes-base.stopAndError", "typeVersion": 1, "position": [800, 400], "parameters": {}})
    branch["connections"]["Call"] = {"main": [[{"node": "Respond", "type": "main", "index": 0}], [{"node": "Stop", "type": "main", "index": 0}]]}
    assert lint(branch)[0] == [], lint(branch)[0]

    # a sub-workflow (executeWorkflowTrigger) needs no strategy of its own — the caller owns it
    sub = json.loads(json.dumps(good))
    del sub["settings"]["errorWorkflow"]
    sub["nodes"][1] = {"name": "Hook", "type": "n8n-nodes-base.executeWorkflowTrigger", "typeVersion": 1.1, "position": [200, 0], "parameters": {}}
    sub["nodes"][4] = {"name": "Respond", "type": "n8n-nodes-base.set", "typeVersion": 3.4, "position": [600, 0], "parameters": {}}
    assert lint(sub)[0] == [], lint(sub)[0]

    bad = json.loads(json.dumps(good))
    del bad["settings"]["errorWorkflow"]                                      # no strategy
    bad["nodes"][2]["parameters"]["v"] = "={{ $json.a.map(x => x[0] }}"      # missing paren
    bad["nodes"][2]["continueOnFail"] = True                                  # successor Call does not check error
    bad["nodes"][2]["notes"] = "justified"                                    # notes no longer exempt
    bad["nodes"][3]["retryOnFail"] = False                                    # warn
    bad["settings"]["availableInMCP"] = False                                 # untestable
    bad["nodes"].append({"name": "Lost", "type": "n8n-nodes-base.code", "typeVersion": 2, "position": [401, 1], "parameters": {"jsCode": " "}})
    bad["nodes"].append({"name": "Env", "type": "n8n-nodes-base.code", "typeVersion": 2, "position": [1000, 1], "parameters": {"jsCode": "const k = $env.KEY; const c = require('crypto'); return [];"}})
    bad["connections"]["Agent"] = {"main": [[{"node": "Env", "type": "main", "index": 0}]]}
    del bad["connections"]["Hook"]                                            # dead trigger + Set orphan
    b, w = lint(bad)
    rules = sorted(x["rule"] for x in b)
    assert rules == ["dead-trigger", "empty-code", "expression", "masked-error", "no-error-strategy", "not-mcp-testable", "orphan", "orphan"], rules
    assert sorted(x["rule"] for x in w) == ["code-env-access", "overlap", "retry-missing"], w
    assert [x["rule"] for x in lint({"nodes": [], "connections": {}})[0]] == ["empty-compile"]
    print("lint-workflow selftest: ok")


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
        print(f"lint-workflow: cannot read {args[0]}: {e}", file=sys.stderr)
        return 2
    blockers, warnings = lint(wf)
    out = {"file": args[0], "passed": not blockers, "blockers": blockers, "warnings": warnings}
    if "--json" in argv:
        print(json.dumps(out, indent=2))
    else:
        for x in blockers:
            print(f"BLOCK  {x['rule']:<18} {x['node'] or '-':<30} {x['msg']}")
        for x in warnings:
            print(f"warn   {x['rule']:<18} {x['node'] or '-':<30} {x['msg']}")
        print(f"lint-workflow: {'PASS' if not blockers else 'FAIL'} — {len(blockers)} blocker(s), {len(warnings)} warning(s)")
    return 0 if not blockers else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
