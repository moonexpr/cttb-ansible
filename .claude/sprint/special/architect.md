# Sprint Overlay — ARCHITECT

This file is injected by the orchestrator when spawning ARCHITECT in a sprint session. It contains sprint-specific operational protocol. Your base identity and principles are in your agent profile.

---

## Phase Entry

**Read state first** — before reading any other artifact:

```bash
python3 .claude/sprint/tools/sprint_data.py state read
```

Check for `WARN:` lines. If any appear, report them to DIRECTOR before proceeding — state recovery is DIRECTOR's responsibility, not yours. If state reads cleanly, use the JSON to confirm your phase number, which tasks are already complete, and which blockers are open. Do not rely on memory from a prior invocation.

---

## Task Entries in SPRINT_PLAN.md

Write task entries into the phase section of `SPRINT_PLAN.md`:

```markdown
### Task N — [Name]
**Depends:** none | Task M, Task K
**Subsystems:** [which subsystems are touched]
**Contract requirements:** [what each subsystem must provide or consume at its boundaries]
**Constraints:** [concurrency invariants, dependency direction, error propagation]
**Acceptance criteria:** [observable behavior at subsystem boundaries that eval will verify]
**Planning note:** [optional — include when the task cannot be fully scoped without source exploration]
```

After decomposing, register tasks in the shared task list:
```bash
TaskCreate(task_name, depends=[...])
```

---

## On Task PASS

Commit changes, mark task complete, unblock dependents, record task metrics:

```bash
git add -A && git commit -m "task: [task name]"
```

Then record task metrics:
```bash
python3 .claude/sprint/tools/sprint_data.py task \
  --id N \
  --cycles C \
  --blockers B \
  --had-planning-note [true|false] \
  --depends "[Task M, Task K]" \
  --context-chars <len> \
  --plan-clarity <1-5> \
  --interface-completeness <1-5> \
  --friction-notes "..."
```

---

## Phase Completion

When all tasks are complete or deferred:

1. Ensure all task data is recorded via `sprint_data.py`
2. Ensure `BLOCKERS.md` is current for this phase
3. Write a phase eval summary to the phase section of `SPRINT_PLAN.md`:

```
Phase N eval summary: [N] tasks completed, [N] deferred, [N] eval cycles total.
Acceptance criteria status: [met / partially met / missed — specify which].
Arc fidelity: [faithful / drifted — describe if drifted].
Open items for DIRECTOR: [any unresolved questions not yet in BLOCKERS.md].
```

4. Go idle. The `TeammateIdle` hook will fire and signal DIRECTOR to close the phase.

---

## Subagent Turn Cap

Complete your work within 40 turns per invocation. If you exceed this budget on a task, report a blocker to DIRECTOR rather than continuing to accumulate context.
