---
name: stack-intake
description: "Guided interview that turns a rough idea into a PRP-style use-case description ready for /n8n-autopilot:build-stack-v2. Classic question-by-question format aimed at people NOT yet experienced with n8n — it asks about overall inputs, outputs, a concrete worked example, expected behavior, external systems, volume, and failure handling, then synthesizes the answers (using n8n decomposition knowledge) into a structured PRP file. Use when the user has an automation idea but no clear spec, says 'help me plan an n8n workflow/stack', 'I want to automate X but don't know how', or before running build-stack-v2 without a written use case."
argument-hint: '"<one-line idea>"  (optional — the interview fills in the rest)'
user-invocable: true
allowed-tools: Read, Write, Glob, Bash(npx:*), AskUserQuestion
---

# Stack Intake — guided PRP interview

Most people can describe **what they want** ("when a lead comes in, research it and tell me if it's
worth chasing") but not **how to wire it in n8n**. This skill bridges that: a friendly, classic
interview that draws out inputs, outputs, and concrete examples, then writes a **PRP-style use-case
description** that [`/n8n-autopilot:build-stack-v2`](../build-stack-v2/SKILL.md) can decompose into a
real workflow stack. You do the n8n thinking; the user only describes their world.

## Principles

- **One topic at a time.** Ask, listen, follow up. Do NOT dump all questions at once — this is an
  interview, not a form. Adapt: skip what's already obvious, dig where it's vague.
- **Speak their language, not n8n's.** Never ask "what trigger type?" Ask "how does this start — does
  someone fill a form, does it run on a schedule, does an email arrive?" Map their answer to n8n
  concepts yourself.
- **Always anchor on a concrete example.** Abstract specs decompose badly. Make them walk one real case
  end-to-end ("Okay — a lead named *Acme GmbH* arrives. What happens first? Then?").
- **You hold the n8n knowledge.** Use what you know about decomposition (single-responsibility leaves,
  fan-out/fan-in for lists, error boundaries, large-data batching, human-in-the-loop) to ask the RIGHT
  follow-ups — but never make the user learn it. If unsure of an n8n capability, you may consult the
  `n8nac-cheatsheet` / `n8n-orchestration-patterns` skills, not the user.

## The interview (cover every section; adapt the wording)

Use `AskUserQuestion` for the closed choices (trigger family, volume, error policy, HITL) so the user
just clicks; use plain conversation for the worked example and free descriptions.

1. **The goal in one sentence.** "In one line, what should this automation achieve?" (Seed from
   `$ARGUMENTS` if given.)
2. **How it starts (input / trigger).** A schedule? A webhook/form someone submits? An incoming email?
   A chat message? A manual run? — *and* what data comes with it. Ask for a **concrete example of the
   input** (a sample form, an example email, a row of data).
3. **What "done" looks like (output).** When it finishes, what exists that didn't before, and **where**
   does it land — a Slack message, a Notion page, a row in a database, a sent email, a file? Ask for an
   **example of the finished result**.
4. **One worked example, end-to-end.** Walk a single real case from trigger to output, step by step, in
   their words. This is the most important answer — capture it verbatim.
5. **External systems & accounts.** Which apps/services does it touch (Slack, Notion, Gmail, a CRM, an
   LLM, a database, a scraping API …)? Each one likely needs a credential — note them, don't set them up.
6. **Volume & batching.** One thing at a time, or a list/batch? Roughly how many per run? (This decides
   fan-out/fan-in and large-data handling — infer it, don't quiz them on it.)
7. **When something goes wrong.** If a step fails (an API down, a record missing), should it stop and
   alert, skip that item and continue, or retry? (Maps to error boundaries.)
8. **Human checkpoints.** Any step where a person must review/approve before it proceeds?
9. **Reuse & scope.** Is any part of this already done elsewhere, or useful on its own? Anything
   explicitly **out of scope** for now?

If the user is stuck on a question, offer 2–3 concrete examples to react to rather than leaving it open.

## Synthesize → write the PRP

When the sections are covered, synthesize (do not just transcribe) into this structure and write it to
`docs/stack-prps/<stack-slug>.prp.md` (create the dir; `<stack-slug>` = kebab-case of the goal). Convert
the user's prose into n8n-flavoured signals where you confidently can, but **never invent requirements
they didn't state** — mark genuine gaps as `OPEN:`.

```markdown
# <Stack name> — Use-Case PRP

> Intake interview <date>. Feeds /n8n-autopilot:build-stack-v2.

## Goal
<one-paragraph outcome>

## Trigger & input
- **Starts via:** <schedule / webhook / form / email / chat / manual>
- **Incoming data:** <fields>
- **Example input:**
  ```
  <concrete sample the user gave>
  ```

## Desired output
- **Result:** <what exists when done>
- **Lands in:** <Slack / Notion / DB / email / file>
- **Example output:** <concrete sample>

## Worked example (end-to-end)
<the user's one real case, trigger → output, in clear steps>

## External systems & credentials
- <system> — <why> — credential: <type or OPEN>

## Volume & batching
<one item vs list; rough count; implication for fan-out / batching>

## Error handling
<stop-and-alert / skip-and-continue / retry, per the user's answer>

## Human-in-the-loop
<any approval/review steps, or "none">

## Reuse & scope
- Reusable / standalone parts: <…>
- Out of scope: <…>

## Decomposition hints (for the architect — derived, not user-stated)
<your read: likely leaves, where a fan-out/fan-in applies, error/large-data boundaries, the entry orchestrator>
```

## Hand off

After writing the file, show the user a short summary and offer the next step verbatim:

> PRP written to `docs/stack-prps/<slug>.prp.md`. Run it with:
> `/n8n-autopilot:build-stack-v2 "<paste the Goal + key sections, or 'see docs/stack-prps/<slug>.prp.md'>"`

Do **not** auto-run build-stack-v2 — building deploys workflows to the instance; that needs an explicit
go from the user. If they confirm, pass the PRP content as the `description` arg to build-stack-v2.

## Limits

- This skill only **plans** — it never touches the n8n instance and writes nothing but the PRP file.
- The quality of the stack depends on the worked example. If the user can't give one concrete case,
  say so in the PRP (`OPEN: no concrete example`) rather than guessing the behavior.
