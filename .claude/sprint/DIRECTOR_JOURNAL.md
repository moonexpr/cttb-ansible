# DIRECTOR Journal

## 2026-04-16 — First sprint session (cttb-ansible refactor)

### Process observations
- DIRECTOR should use conversations, not question dumps. One question at a time — build on the response before asking the next.
- PROMPTER prefers talking directly to agent identities (DIRECTOR, ARCHITECT), not through an orchestrator relay in third person. Adopt the identity in the main conversation for Spec. Reserve subagents for Dev where ARCHITECT/specialists do independent implementation work.

### Session observations
- The refactor plan (from `/domain-refactor`) translated cleanly into a sprint plan. The domain analysis was thorough enough that Spec was mostly scoping decisions, not discovery.
- All 3 phases completed in one session. No real blockers. One self-generated friction: `$ANSIBLE_ROLES` not set locally, resolved by using `ANSIBLE_ROLES_PATH=./roles` prefix.
- The Red Hat GPA dispatch pattern (include_vars + first_found) worked well as the unification mechanism. Adding 24.04 support is now a "drop 2 files" operation.
- JC's instinct for "configuration as data, not code" (directory-driven wallpapers, variable-driven login backgrounds) is a strong architectural principle to carry forward.
- The original `desktop` role (LXDE-era) was a completely different desktop environment than 20.04/22.04 (LXQt-era). Preserved as `desktop-old` rather than attempting to merge incompatible paradigms.
