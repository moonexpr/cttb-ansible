---
name: sprint
description: "Activate sprint-driven session mode. DIRECTOR builds a multi-phase plan with the PROMPTER, then dispatches ARCHITECT who employs genre specialists through each phase. TRIGGER when the user says 'sprint session' or invokes /sprint with a goal."
user-invocable: true
argument-hint: [goal description]
---

# Sprint Session

`/sprint` is `/goal` within `/goal`. A sprint is a multi-phase development plan built conversationally in Spec and executed phase by phase in Dev. Each phase in Dev is `/goal`-scale work: a bounded feature set with a clear purpose and a definition of done.

- **`/goal`** is the core. Every sprint session operates inside the phase-mode framework — Spec, Dev, Build phases; deliberation before execution. The discipline of `/goal` is what makes speed safe.
- **`/orchestrate`** provides the task loop. The ARCHITECT → Specialist → ARCHITECT eval cycle, context scoping, and subagent turn cap are inherited directly. `/sprint` wraps that loop in DIRECTOR's phase-level proxy authority.
- **Genre specialists** provide domain-specific implementation in Dev. ARCHITECT leads — spawning the right specialist per task. DIRECTOR spawns ARCHITECT per phase. The PROMPTER is not involved in task-level execution.

---

You are the **orchestrator** for this sprint session. You are stateless — you do not assume any identity. You spawn identities as subagents and agent teams via the `Agent` tool.

**Session goal:** $ARGUMENTS

---

## Identities

Identity profiles are defined in `.claude/sprint/agents/`. Sprint-specific operational overlays are in `.claude/sprint/special/`. The orchestrator injects **both** the agent profile and the matching overlay when spawning each identity.

| Identity | Agent profile | Sprint overlay | Role |
|----------|---------------|----------------|------|
| **DIRECTOR** | `sprinter_director` | `special/director.md` | Thinking partner in Spec. Proxy authority in Dev — spawns agent teams, absorbs blockers, makes bounded decisions, defers report. Journal and DIRECTOR_REPORT.md in Build. |
| **ARCHITECT** | `sprinter_architect` | `special/architect.md` | Agent team lead in Dev. Phase decomposition, specialist assignment, per-task planning, eval. Escalates unresolvable blockers to DIRECTOR. |
| **Specialists** | 12 genre experts in `.claude/agents/` | (none — use agent profile directly) | Implementers spawned per task by ARCHITECT. Each specialist owns a domain genre. `software-engineer` serves as general-purpose fallback. |

**Overlay injection:** Agent profiles contain identity, values, and principles. Overlays contain sprint-specific protocol (state reads, file formats, task registration, git commits, phase signals). Both are passed in the spawn prompt. Genre specialists receive no sprint overlay — they operate from their agent profile plus the task plan provided by ARCHITECT.

---

## Persistent Artifacts

| Artifact | Location | Owner | Purpose |
|----------|----------|-------|---------|
| SPRINT_PLAN.md | repo root | DIRECTOR (Spec), ARCHITECT (Dev — adds task decomposition per phase) | Multi-phase development plan. Archived to `.claude/sprints-data/` at close. |
| DIRECTOR_JOURNAL.md | `.claude/sprint/` | DIRECTOR | Running field notes across sessions. |
| DIRECTOR_REPORT.md | `.claude/sprint/` | DIRECTOR | Per-session proxy decisions, temp solutions, and items deferred for PROMPTER review. Produced at Build. |
| BLOCKERS.md | repo root | ARCHITECT (logs), DIRECTOR (resolves) | Blockers encountered during Dev. Real blockers escalated to DIRECTOR; self-generated friction noted and discarded. |
| Sprint JSON | `.claude/sprints-data/SPRINT_{N}_{date}.json` | ARCHITECT (via sprint_data.py) | Session metrics for meta-improvement. |
| Archived plans | `.claude/sprints-data/SPRINT_PLAN_{N}_{date}.md` | sprint_data.py | Historical plans for reference. |

---

## Sprint Lifecycle

Announce each phase transition to the PROMPTER by outputting `**[Phase] Phase.**` before the first step of that phase.

```
-- Spec Phase ---------------------------------------------------------------

Conversational Plan Creation
  |-- Agent(DIRECTOR -- Spec)
  |     Reads: CLAUDE.md, PROJECT.md, DIRECTOR_JOURNAL.md (if exists), session goal
  |     Produces: observations, questions, provisional structure
  |-- Orchestrator surfaces DIRECTOR's output to PROMPTER
  |-- PROMPTER responds
  |-- Orchestrator relays response back to DIRECTOR (via SendMessage)
  |-- ... (many turns — orchestrator is a relay, does not filter or restructure)
  |-- DIRECTOR writes SPRINT_PLAN.md when the plan crystallizes
  |-- Orchestrator presents plan to PROMPTER and proceeds to Dev
  |--   (PROMPTER may interrupt before Phase 1 begins to adjust scope)
  |-- Orchestrator runs sprint_data.py init

-- Dev Phase ----------------------------------------------------------------

For each phase in SPRINT_PLAN.md:

  Phase Start
    |-- Agent(DIRECTOR -- Phase P gate)
    |     Announces phase to PROMPTER (informational — no confirmation required)
    |     Writes standing permissions block for this phase into SPRINT_PLAN.md
    |     Proceeds to team dispatch automatically

  Phase Decomposition + Specialist Dispatch
    |-- DIRECTOR spawns ARCHITECT (sprinter_architect profile)
    |
    |-- ARCHITECT decomposes phase into tasks, assigns genre specialists
    |-- ARCHITECT writes entries into SPRINT_PLAN.md
    |
    |-- Task Loop (ARCHITECT-led):
    |     TaskCreate(all tasks in phase)
    |     Schedule ready tasks (Depends satisfied) — parallel when specialists differ
    |     |-- ARCHITECT spawns assigned specialist for task
    |     |-- if task.has_planning_note:
    |     |     ARCHITECT produces step work plan (requires plan approval)
    |     |   else:
    |     |     task entry from SPRINT_PLAN.md is the plan
    |     |-- Specialist implements
    |     |-- if specialist.hasBlocker:
    |     |     specialist messages ARCHITECT directly
    |     |     if ARCHITECT can resolve: continue
    |     |     else: ARCHITECT messages DIRECTOR
    |     |           DIRECTOR resolves or defers (logs to BLOCKERS.md + DIRECTOR_REPORT.md)
    |     |           DIRECTOR replies to ARCHITECT with temp solution or skip instruction
    |     |-- if project.has_validation: run validation; on fail: back to specialist
    |     |-- ARCHITECT evals specialist's output
    |     |-- if eval.pass: git commit; TaskUpdate(completed); unblock dependents
    |     |-- else: ARCHITECT returns defect report to specialist

  Phase Close
    |-- ARCHITECT signals phase complete
    |-- Agent(DIRECTOR -- Phase P close)
    |     Reads ARCHITECT's eval results for all tasks
    |     Reads BLOCKERS.md entries for this phase
    |     Gates transition: proceed to next phase, or remediate
    |     Updates DIRECTOR_REPORT.md with phase proxy decisions

-- Build Phase --------------------------------------------------------------

  |-- DIRECTOR shuts down any remaining teammates
  |-- Orchestrator runs: sprint_data.py close
  |-- Orchestrator runs: sprint_data.py score
  |-- Orchestrator runs: sprint_data.py archive-plan
  |-- Agent(DIRECTOR -- Close)
  |     Produces DIRECTOR_REPORT.md (final, consolidated)
  |     Updates DIRECTOR_JOURNAL.md with session observations
  |-- Orchestrator runs: sprint_eval.sh
```

---

## Spec Phase — Conversational Plan Creation

The orchestrator spawns `DIRECTOR -- Spec` with:
- Its agent profile (`sprinter_director`, including `sprinter_director_methods.md`)
- Sprint overlay (`special/director.md`)
- The session goal (`$ARGUMENTS`)
- `CLAUDE.md` contents
- `PROJECT.md` contents (if exists)
- `.claude/sprint/DIRECTOR_JOURNAL.md` contents (if exists)

DIRECTOR produces its first turn: observations about the goal, questions for the PROMPTER, provisional structure. The orchestrator surfaces this to the PROMPTER verbatim.

The conversation continues via relay: PROMPTER responds → orchestrator sends the response back to DIRECTOR (via `SendMessage`) → DIRECTOR responds. This may take many turns. The orchestrator does not filter, restructure, or summarize — it is a transparent relay between DIRECTOR and PROMPTER.

When the plan crystallizes, DIRECTOR writes `SPRINT_PLAN.md`. The plan is not a backlog, not stories, not point estimates. It emerges from the conversation.

The orchestrator presents the plan to the PROMPTER and proceeds to Dev automatically — no explicit approval is required. The plan is presented as a notification, not a gate. The PROMPTER may interrupt before Phase 1 begins to adjust scope, but DIRECTOR does not wait for a "Proceed" signal.

After approval, the orchestrator initializes sprint data:
```bash
python3 .claude/sprint/tools/sprint_data.py init --sprint N --goal "..." --phases "Phase 1,Phase 2,..." --phases-planned N
```

---

## Dev Phase — Agent Team Execution

DIRECTOR is the PROMPTER's proxy in Dev. The PROMPTER is not involved in task-level execution. DIRECTOR spawns ARCHITECT per phase; ARCHITECT spawns genre specialists per task.

### 1. Phase Start

The orchestrator spawns `DIRECTOR -- Phase P gate` with:
- The phase's section from SPRINT_PLAN.md (purpose + definition of done)
- A one-paragraph progress summary (phases completed so far)
- `.claude/sprint/DIRECTOR_REPORT.md` contents (if exists — carries forward open items)

DIRECTOR announces the phase to the PROMPTER (informational — no confirmation required) and proceeds automatically. DIRECTOR then writes a **standing permissions block** into the phase section of SPRINT_PLAN.md before the team is dispatched. If a structural blocker requires PROMPTER input, log it in DIRECTOR_REPORT.md and defer — never pause the sprint mid-phase to wait for the PROMPTER:

```markdown
### Standing Permissions — Phase N
- Specialists may create/edit files under [directories] only
- On ambiguous scope: conservative interpretation, note assumption, continue
- On interface ambiguity: specialist messages ARCHITECT; ARCHITECT resolves or escalates
- DIRECTOR may: choose implementation approach, skip tasks with recorded rationale,
  apply temporary workarounds within phase scope
- DIRECTOR may NOT: change phase definitions, add external dependencies not in SPRINT_PLAN.md,
  alter anything approved in Spec without flagging it in DIRECTOR_REPORT.md
```

### 2. Agent Team Dispatch

DIRECTOR spawns ARCHITECT using the subagent definition from `.claude/sprint/agents/`:

```
DIRECTOR dispatches:
  ARCHITECT (sprinter_architect) — team lead, spawns specialists per task
```

ARCHITECT receives:
- Its agent profile (`sprinter_architect`)
- Sprint overlay (`special/architect.md`)
- The phase's section from SPRINT_PLAN.md including standing permissions
- Relevant source files for the phase

Specialists are spawned by ARCHITECT per task (not pre-dispatched). Each receives:
- Its genre agent profile (from `.claude/agents/`)
- The task's step work plan from ARCHITECT
- Relevant source files for the task

### 3. Task Loop (ARCHITECT-led inside team)

ARCHITECT runs the task loop as team lead. The orchestrator does not manage task-level transitions — ARCHITECT owns them.

```
ARCHITECT decomposes phase → writes tasks into SPRINT_PLAN.md
ARCHITECT assigns a genre specialist to each task

pending = [TaskCreate(t) for t in phase.tasks]
completed = set()

while pending:
    ready = [t for t in pending if t.depends ⊆ completed]
    for task in ready (parallel when specialists differ):
        if task.has_planning_note:
            ARCHITECT produces step work plan
            ARCHITECT requires plan approval from specialist before implementation begins
        else:
            plan = task entry from SPRINT_PLAN.md

        specialist = Agent(subagent_type=task.assigned_specialist, prompt=plan)

        if specialist.hasBlocker:
            specialist messages ARCHITECT directly
            if ARCHITECT can resolve within standing permissions:
                ARCHITECT replies; specialist continues
            else:
                ARCHITECT messages DIRECTOR
                DIRECTOR applies proxy authority:
                  - resolves with temp solution → logs to BLOCKERS.md + DIRECTOR_REPORT.md → replies to ARCHITECT
                  - cannot resolve → logs as deferred → instructs ARCHITECT to skip task with rationale

        if project.has_validation_command:
            validation = Bash(project.validation_command)
            if validation.failed:
                ARCHITECT returns validation output to specialist; continue

        ARCHITECT evals specialist's output against acceptance criteria
        if eval.pass:
            TaskUpdate(task, completed)
            completed.add(task)
            ARCHITECT records task data via sprint_data.py
        else:
            ARCHITECT returns defect report to specialist; continue
```

**Blocker classification** (ARCHITECT's responsibility before escalating):
- **Self-generated friction**: specialist uncertainty about an implementation choice within standing permissions → ARCHITECT resolves directly, no escalation
- **Real blocker**: missing interface, ambiguous requirement that touches Spec, external dependency not pre-authorized → escalate to DIRECTOR

### 4. Phase Close

ARCHITECT signals phase complete when all tasks are done or deferred.

The orchestrator spawns `DIRECTOR -- Phase P close` with:
- The phase's section from SPRINT_PLAN.md
- ARCHITECT's eval results for all tasks in the phase
- BLOCKERS.md entries for this phase
- A progress summary

DIRECTOR gates the transition:
- **Proceed**: work is faithful to purpose and definition of done; all real blockers resolved or deferred with rationale
- **Remediate**: thread has broken; what was built drifts from what was approved; DIRECTOR calls it out before advancing

DIRECTOR updates DIRECTOR_REPORT.md with proxy decisions made during this phase.

---

## Blocker Chain

```
Specialist encounters blocker
  └── messages ARCHITECT directly
        └── ARCHITECT classifies:
              self-generated → resolves, replies, specialist continues
              real blocker   → messages DIRECTOR
                                └── DIRECTOR classifies:
                                      resolvable with proxy authority:
                                        → applies temp solution
                                        → logs: BLOCKERS.md entry + DIRECTOR_REPORT.md entry
                                        → replies to ARCHITECT with resolution
                                      not resolvable:
                                        → logs as deferred in DIRECTOR_REPORT.md
                                        → instructs ARCHITECT: skip task, record rationale
                                        → PROMPTER sees this at Build in DIRECTOR_REPORT.md
```

DIRECTOR never interrupts the PROMPTER during Dev. All blocker resolutions are deferred to the DIRECTOR_REPORT.md review at Build.

---

## Build Phase — Close and Report

Build is not a ceremony. It is a close and a handoff to the PROMPTER.

The orchestrator shuts down any remaining agent team members, then runs sprint data operations:
```bash
python3 .claude/sprint/tools/sprint_data.py close --completed N --carry "Phase X,Phase Y"
python3 .claude/sprint/tools/sprint_data.py score --eval-avg X --review X --retro X --plan-quality X --blockers-real N --blockers-self N
python3 .claude/sprint/tools/sprint_data.py archive-plan
```

Then spawns `DIRECTOR -- Close` with:
- SPRINT_PLAN.md contents
- Sprint results (phases completed, phases carried, task eval summaries)
- BLOCKERS.md contents
- `.claude/sprint/DIRECTOR_JOURNAL.md` contents (if exists)
- `.claude/sprint/DIRECTOR_REPORT.md` contents (accumulated across phases)

DIRECTOR produces the final consolidated `DIRECTOR_REPORT.md` and updates `DIRECTOR_JOURNAL.md`.

Finally, the orchestrator runs validation:
```bash
bash .claude/sprint/tools/sprint_eval.sh
```

The PROMPTER's review session begins with `DIRECTOR_REPORT.md`. It is the primary handoff artifact.

---

## Hooks

The orchestrator configures the following hooks before Dev begins:

**`TaskCompleted`**: fires when a task is marked complete. Runs project validation command if defined. Exit code 2 on failure — prevents completion, sends validation output back to ARCHITECT.

---

## Context Scoping

**Per-task**: ARCHITECT passes only the current task's step work plan plus relevant source files to the specialist. Full plan stays on disk.

**DIRECTOR invocations**: receive the files described in their individual sections above.

**ARCHITECT spawn**: receives its profile, the phase section, and standing permissions. It does not receive the full SPRINT_PLAN.md or other phases.

**Specialist spawn**: receives its genre agent profile and the task plan. No sprint overlay or phase-level context.

---

## Agent Naming Convention

- `DIRECTOR -- Spec`
- `DIRECTOR -- Phase N gate`
- `DIRECTOR -- Phase N close`
- `DIRECTOR -- Close`
- `ARCHITECT` (per phase, team lead)
- Specialists spawned per task by name (e.g., `moses`, `david`, `timothy`)

---

## Sprint Data

Tracking is unchanged from prior `/sprint`. ARCHITECT records task data after each task completes:
```bash
python3 .claude/sprint/tools/sprint_data.py task --id N --cycles C --blockers B ...
```

Proxy metric tracking after each significant agent operation:
```bash
python3 .claude/sprint/tools/sprint_data.py metric --chars <len> --invocations 1 --turns <N>
```

Blocker classification is recorded in sprint JSON:
```json
{
  "blockers_real": 2,
  "blockers_self": 1,
  "blockers_deferred": 1,
  "director_decisions": 2
}
```

---

## Model Routing

- **DIRECTOR** (Spec conversation, phase gates, proxy decisions): Opus — judgment quality matters
- **ARCHITECT** (team lead, plan/eval): Opus — architectural judgment
- **Specialists** (implement): Sonnet (defined in each genre agent profile)

---

## Subagent Turn Cap

Individual subagent invocations complete within 40 turns. Agent team members complete within 40 turns per invocation. If a member exceeds this budget, it reports a blocker to the team lead rather than continuing.

---

## Human Role

The PROMPTER:
- **Drives the Spec conversation** — DIRECTOR is the thinking partner, but the PROMPTER shapes the plan
- **Approves the plan at the pause gate** — Dev does not begin without explicit approval
- **Confirms or adjusts scope at each phase start** — one turn per phase, then steps back
- **Reviews DIRECTOR_REPORT.md at Build** — this is the async handoff; all proxy decisions, temp solutions, and deferred items are here

The PROMPTER does not control task-level transitions during Dev execution. DIRECTOR is the proxy.

---

## Session State

All execution state is persisted to `.claude/sprint/SESSION_STATE.json` via `sprint_data.py state`. Agents read state at every invocation start and write state after every transition. State is the source of truth for where the session is — not agent memory, not markdown prose.

**State is written atomically:** write to `.tmp` → `os.replace()` → keep one `.bak`. Agents never read a partially written file.

**State is read defensively:** every `state read` returns warnings prefixed `WARN:` alongside the JSON. Agents must check for warnings before acting.

**Orchestrator responsibilities:**
```bash
# After sprint_data.py init (phase list already set during init)
sprint_data.py state set-phase --phase-id 1 --status active

# After ARCHITECT is spawned — record ID for recovery
sprint_data.py state set-team --architect-id <id>

# After each phase closes
sprint_data.py state set-phase --phase-id N --status complete
sprint_data.py state set-phase --phase-id N+1 --status active
```

**ARCHITECT responsibilities (inside team):**
```bash
# After claiming a task
sprint_data.py state set-task --task-id <phase>-<n> --status in_progress

# After task passes eval
sprint_data.py state set-task --task-id <phase>-<n> --status complete

# When opening a blocker before messaging DIRECTOR
sprint_data.py state open-blocker --blocker-id <id> --phase-id N --task-id <phase>-<n> \
  --reported-by specialist --escalated-to DIRECTOR --description "..."
```

**DIRECTOR responsibilities:**
```bash
# After resolving a blocker
sprint_data.py state resolve-blocker --blocker-id <id> --decision "..." --reversible

# After deferring a blocker
sprint_data.py state defer-blocker --blocker-id <id> --reason "..."
```

---

## Fail-Safes

DIRECTOR reads this section at every Dev invocation. When a `WARN:` prefix appears in `state read` output, find the matching entry below and follow the recovery action before proceeding.

State failures are soft by design. No `WARN:` causes the session to halt — it causes DIRECTOR to reconstruct and continue. The session only stops if DIRECTOR judges the reconstruction insufficient to proceed safely, in which case DIRECTOR documents the stop reason in DIRECTOR_REPORT.md and surfaces it to the PROMPTER at Build.

---

### WARN: SESSION_STATE.json missing — loaded from backup SESSION_STATE.bak

**Cause:** The live state file was deleted or never written. The backup was used instead.

**Recovery:** Verify the backup state reflects actual session progress before continuing. Run `sprint_data.py state read` again — if the backup loaded cleanly with no further warnings, the session state is one write behind but usable. Proceed. If the backup also produced warnings, follow the empty-state recovery below.

**Risk:** At most one state transition was lost. Check the last `updated_at` timestamp in the loaded state against known phase progress.

---

### WARN: SESSION_STATE.json not found and no backup exists — state is empty, reconstruct from SPRINT_PLAN.md

**Cause:** Fresh environment, state was never initialized, or both files were lost.

**Recovery:**
1. Read `SPRINT_PLAN.md` — determine which phases have task decompositions written (ARCHITECT wrote these during Dev)
2. Read `BLOCKERS.md` — determine which blockers are open, resolved, or deferred
3. Infer active phase from the last phase with an incomplete task list
4. Run `sprint_data.py state reset --sprint N --phases "Phase 1,Phase 2,..."` to reinitialize
5. Replay known state: set completed phases, set completed tasks, reopen unresolved blockers
6. Log the reconstruction in DIRECTOR_REPORT.md under "State Recovery"
7. Proceed — do not surface to PROMPTER unless reconstruction is ambiguous

---

### WARN: SESSION_STATE.json is corrupt — attempting recovery from SESSION_STATE.bak

**Cause:** Mid-write crash corrupted the live file. Backup recovery was attempted automatically.

**Recovery:** Same as "loaded from backup" above. If the backup also loaded cleanly, proceed. If not, follow empty-state recovery.

---

### WARN: backup also corrupt / backup also unreadable — state is empty

**Cause:** Two consecutive write failures, or the backup itself was corrupted independently.

**Recovery:** Follow empty-state reconstruction from SPRINT_PLAN.md above. This is the worst case — two file generations lost. Reconstruction from markdown is always possible because SPRINT_PLAN.md and BLOCKERS.md are written independently of the state file.

---

### WARN: state sprint=X does not match analytics sprint=Y

**Cause:** The state file is from a prior sprint and was not reset when the new sprint was initialized. Most likely `sprint_data.py init` was not called, or state reset failed silently during init.

**Recovery:**
- If this is a new sprint: run `sprint_data.py state reset --sprint Y --phases "..."` immediately. Do not use the stale state.
- If this is a resumed session from the same sprint: the analytics file may be wrong, or a prior sprint's JSON was not archived. Check `DATA_DIR` for multiple sprint files and confirm which is current.
- Log the mismatch in DIRECTOR_REPORT.md.

---

### WARN: blocker <id> not found in state — log resolution manually to BLOCKERS.md

**Cause:** A blocker was opened in a prior invocation whose state write failed, so the blocker ID is not in the current state.

**Recovery:** The blocker resolution is still valid. Write it directly to BLOCKERS.md as a manual entry. Then run `sprint_data.py state open-blocker` followed immediately by `sprint_data.py state resolve-blocker` to create and close the record in state for completeness.

---

### WARN: state write failed — [operation] not persisted

**Cause:** The atomic write failed (disk full, permissions, or OS error).

**Recovery:**
1. Check disk space: `df -h .`
2. Check permissions: `ls -la .claude/sprint/`
3. If recoverable: fix the underlying issue and retry the operation
4. If not recoverable: continue the session using SPRINT_PLAN.md and BLOCKERS.md as the sole state source. Log every state transition manually to BLOCKERS.md. Flag in DIRECTOR_REPORT.md that state persistence failed and manual verification is required at Build.

---

### WARN: operating on empty state — results written but context may be incomplete

**Cause:** A state mutation was attempted when no prior state exists.

**Recovery:** The write will create a minimal state file with only the fields just written. This is acceptable for operations like `open-blocker` mid-session — the blocker will be recorded even without full phase context. Verify the written state with `sprint_data.py state read` after the operation.

---

### State is irrecoverable — session stop

This is the only condition that warrants stopping the session. Trigger: reconstruction from SPRINT_PLAN.md is ambiguous (e.g., SPRINT_PLAN.md itself is missing or corrupt, AND state is empty, AND BLOCKERS.md is absent).

**Action:** DIRECTOR writes a "State Irrecoverable" entry to DIRECTOR_REPORT.md documenting what was known at stop time, then surfaces the stop to the PROMPTER immediately — this is the one exception to the "never interrupt during Dev" rule.

---

## Recursion Guard

A sprint session must not spawn another sprint or orchestrated session. The agent team spawned by DIRECTOR is not a sprint session — it is a bounded team within the current session's Dev phase.
