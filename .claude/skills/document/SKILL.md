---
name: document
user-invocable: true
argument-hint: "<the work or information to record>"
description: >
  Project-scoped router for recording CTTB work or information. Classifies
  one piece of work/knowledge by artifact type and hands it to the right
  channel: durable reference knowledge → `/wiki-author`; an actionable
  defect / task / missing feature → `/github-issues`. Triggers on
  `/document <thing>`, "document this", "write this up", "record this",
  "where should this go", or an agent finishing work that must be recorded
  somewhere. Auto-routes by type and does not duplicate the deeper skills'
  content — it routes and hands back.
---

## When to apply

Apply when there is exactly one thing to record and the question is *which
channel*. If the input bundles several distinct things (a runbook *and* a
bug), split it: route each piece independently, one hand-off per piece. If
there is no recordable artifact (a question, a discussion), do not route —
answer normally. If the input is a session-progress note ("what happened
today", "verified that X works"), that is not a recordable artifact in this
project — surface it in the conversation, don't route.

## Procedure

1. **Read the input.** Identify the single artifact to record. If `$ARGUMENTS`
   is empty, take the most recent concrete result or decision in the
   conversation as the artifact.

2. **Classify by artifact type** (pick exactly one — the first that matches,
   in this order):

   - **Actionable** — a bug, build failure, missing feature, surprising
     behavior, or task that someone must *act on later*. Signal: it implies
     future work, has a repro, or names a defect. → **GitHub issue**.
   - **Durable reference** — how a system works, config, a runbook,
     architecture, a how-to that stays true beyond this session and a future
     reader would look up. Signal: timeless, explanatory, not tied to "this
     run". → **Wiki**.

   State the chosen channel and the one-line reason, then hand off without
   asking. (Auto-route is the configured behavior; do not gate on a
   confirmation question.)

   If the input fits neither (a pure session-progress note, a half-formed
   thought, a question), do not route — say so and stop.

3. **Hand off to the chosen channel:**

   - **GitHub issue** → invoke the `/github-issues` skill with the artifact.
     It owns the full dedup → file → categorize protocol (the CLAUDE.md
     "Issue Filing" encapsulation). Do not inline that protocol here.
   - **Wiki** → invoke the `/wiki-author` skill with the artifact. Let that
     skill own page placement, voice, templates, and the publish/purge
     workflow. Do not hand-roll wiki API calls here.

4. **Hand back.** Report in one line: the channel chosen, and the concrete
   destination (issue URL or wiki page title). Do not continue into unrelated
   work — routing is the whole job.

## Resources

Self-contained. This skill writes no helper scripts and loads no sibling
files. It composes by invoking the existing `/wiki-author` and
`/github-issues` skills. It deliberately does not restate those procedures —
it classifies and hands off.
