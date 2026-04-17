#!/usr/bin/env python3
"""Sprint data management CLI for ARCHITECT. Run from repo root."""
import argparse, json, os, sys, glob, shutil
from datetime import date as Date, datetime

DATA_DIR   = ".claude/sprints-data"
STATE_DIR  = ".claude/sprint"
STATE_FILE = os.path.join(STATE_DIR, "SESSION_STATE.json")
STATE_TMP  = os.path.join(STATE_DIR, "SESSION_STATE.tmp")
STATE_BAK  = os.path.join(STATE_DIR, "SESSION_STATE.bak")

VALID_PHASE_STATUSES = {"pending", "active", "complete", "skipped"}
VALID_TASK_STATUSES  = {"pending", "in_progress", "complete", "deferred", "skipped"}
VALID_BLOCKER_STATUSES = {"open", "resolved", "deferred"}


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def latest_sprint_path():
    files = sorted(glob.glob(os.path.join(DATA_DIR, "SPRINT_*.json")))
    if not files:
        sys.exit(f"error: no sprint data files in {DATA_DIR}")
    return files[-1]


def sprint_path(n, d):
    return os.path.join(DATA_DIR, f"SPRINT_{n}_{d}.json")


def load(path):
    with open(path) as f:
        return json.load(f)


def save(path, data):
    """Non-atomic save for analytics files (unchanged from original)."""
    with open(path, "w") as f:
        json.dump(data, f, indent=2)


def save_atomic(tmp, dest, data):
    """Write to tmp then os.replace() — atomic on POSIX, including macOS."""
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, dest)


# ---------------------------------------------------------------------------
# State helpers
# ---------------------------------------------------------------------------

def state_load_raw():
    """
    Load SESSION_STATE.json. Returns (data, warnings[]).
    Never raises — soft failures only. Warnings are prefixed WARN: for agents.
    """
    warnings = []

    if not os.path.exists(STATE_FILE):
        # Try backup before giving up
        if os.path.exists(STATE_BAK):
            warnings.append("WARN: SESSION_STATE.json missing — loaded from backup SESSION_STATE.bak")
            try:
                with open(STATE_BAK) as f:
                    data = json.load(f)
                return data, warnings
            except (json.JSONDecodeError, OSError) as e:
                warnings.append(f"WARN: backup also unreadable ({e}) — state is empty, reconstruct from SPRINT_PLAN.md")
                return {}, warnings
        warnings.append("WARN: SESSION_STATE.json not found and no backup exists — state is empty, reconstruct from SPRINT_PLAN.md")
        return {}, warnings

    try:
        with open(STATE_FILE) as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        warnings.append(f"WARN: SESSION_STATE.json is corrupt ({e})")
        if os.path.exists(STATE_BAK):
            warnings.append("WARN: attempting recovery from SESSION_STATE.bak")
            try:
                with open(STATE_BAK) as f:
                    data = json.load(f)
                warnings.append("WARN: recovered from backup — verify state before continuing")
                return data, warnings
            except (json.JSONDecodeError, OSError) as e2:
                warnings.append(f"WARN: backup also corrupt ({e2}) — state is empty, reconstruct from SPRINT_PLAN.md")
                return {}, warnings
        warnings.append("WARN: no backup available — state is empty, reconstruct from SPRINT_PLAN.md")
        return {}, warnings
    except OSError as e:
        warnings.append(f"WARN: cannot read SESSION_STATE.json ({e}) — state is empty")
        return {}, warnings

    return data, warnings


def state_validate(data, warnings):
    """
    Cross-check state sprint number against latest analytics file.
    Appends warnings in-place. Returns data unchanged.
    """
    if not data:
        return data

    state_sprint = data.get("sprint")
    if state_sprint is None:
        warnings.append("WARN: state file has no sprint number — cannot validate against analytics")
        return data

    try:
        analytics_path = latest_sprint_path()
        analytics = load(analytics_path)
        analytics_sprint = analytics.get("sprint")
        if analytics_sprint is not None and analytics_sprint != state_sprint:
            warnings.append(
                f"WARN: state sprint={state_sprint} does not match "
                f"analytics sprint={analytics_sprint} — "
                f"you may be reading stale state from a prior sprint"
            )
    except SystemExit:
        warnings.append("WARN: no analytics file found — cannot validate sprint number")

    return data


def state_load():
    """Load, validate, and return (data, warnings). Safe to call at any time."""
    data, warnings = state_load_raw()
    state_validate(data, warnings)
    return data, warnings


def state_save(data):
    """
    Atomic save: backup current → write to tmp → replace.
    Keeps one generation of backup. Never raises.
    Returns (ok, error_string).
    """
    os.makedirs(STATE_DIR, exist_ok=True)
    try:
        if os.path.exists(STATE_FILE):
            shutil.copy2(STATE_FILE, STATE_BAK)
    except OSError as e:
        # Non-fatal — proceed without backup
        print(f"WARN: could not write backup ({e}) — continuing without backup", file=sys.stderr)

    try:
        data["updated_at"] = datetime.now().isoformat(timespec="seconds")
        save_atomic(STATE_TMP, STATE_FILE, data)
        return True, None
    except OSError as e:
        return False, str(e)


def emit(data, warnings):
    """Print warnings then JSON state to stdout."""
    for w in warnings:
        print(w)
    print(json.dumps(data, indent=2))


# ---------------------------------------------------------------------------
# Original commands (unchanged logic, save() unchanged)
# ---------------------------------------------------------------------------

def cmd_init(args):
    os.makedirs(DATA_DIR, exist_ok=True)
    d = args.date or Date.today().isoformat()
    path = sprint_path(args.sprint, d)
    if os.path.exists(path):
        sys.exit(f"error: already exists: {path}")
    data = {
        "sprint":           args.sprint,
        "date":             d,
        "goal":             args.goal,
        "phases":           [s.strip() for s in args.phases.split(",")],
        "phases_planned":   args.phases_planned,
        "phases_completed": None,
        "start_time":       datetime.now().isoformat(timespec="seconds"),
        "end_time":         None,
        "duration_minutes": None,
        "carry_over_phases": [],
        "tasks":            [],
        "proxy_metrics": {
            "context_chars_total": 0,
            "invocation_count":    0,
            "agent_turns_total":   0,
        },
        "architect_scores":        {},
        "engineer_sprint_summary": {},
    }
    save(path, data)
    print(f"init  {path}")

    # Reset session state for new sprint
    phases = [s.strip() for s in args.phases.split(",")]
    state = {
        "sprint":        args.sprint,
        "session":       f"SPRINT_{args.sprint}_{d}",
        "active_phase":  None,
        "phase_status":  {str(i+1): "pending" for i in range(len(phases))},
        "phase_names":   {str(i+1): name for i, name in enumerate(phases)},
        "tasks":         {},
        "team":          {"architect_id": None, "engineer_id": None},
        "open_blockers": [],
        "director_decisions": [],
    }
    ok, err = state_save(state)
    if ok:
        print(f"state reset  {STATE_FILE}")
    else:
        print(f"WARN: analytics init succeeded but state reset failed ({err}) — run: sprint_data.py state --reset --sprint {args.sprint}")


def cmd_task(args):
    path = latest_sprint_path()
    data = load(path)
    tasks = data.setdefault("tasks", [])

    existing = next((t for t in tasks if t.get("id") == args.id), None)
    entry = existing or {"id": args.id}

    if args.cycles is not None:    entry["cycles"]            = args.cycles
    if args.blockers is not None:  entry["blockers"]          = args.blockers
    if args.planning_note:         entry["had_planning_note"] = True
    if args.depends:               entry["depends"]           = [s.strip() for s in args.depends.split(",")]
    if args.chars is not None:     entry["context_chars"]     = args.chars

    fb = entry.setdefault("engineer_feedback", {})
    if args.clarity is not None:      fb["plan_clarity"]           = args.clarity
    if args.completeness is not None: fb["interface_completeness"] = args.completeness
    if args.friction:                 fb["friction_notes"]         = args.friction

    if existing is None:
        tasks.append(entry)

    save(path, data)
    print(f"task  {path}  id={args.id}")


def cmd_metric(args):
    path = latest_sprint_path()
    data = load(path)
    m = data.setdefault("proxy_metrics", {
        "context_chars_total": 0,
        "invocation_count":    0,
        "agent_turns_total":   0,
    })
    m["context_chars_total"] = m.get("context_chars_total", 0) + args.chars
    m["invocation_count"]    = m.get("invocation_count",    0) + args.invocations
    m["agent_turns_total"]   = m.get("agent_turns_total",   0) + args.turns
    save(path, data)
    print(f"metric  chars_total={m['context_chars_total']}  "
          f"invocations={m['invocation_count']}  turns={m['agent_turns_total']}")


def cmd_close(args):
    path = latest_sprint_path()
    data = load(path)
    now = datetime.now().isoformat(timespec="seconds")

    data["phases_completed"] = args.completed
    data["end_time"]         = now

    if data.get("start_time"):
        try:
            start = datetime.fromisoformat(data["start_time"])
            end   = datetime.fromisoformat(now)
            data["duration_minutes"] = int((end - start).total_seconds() / 60)
        except ValueError:
            pass

    if args.carry:
        data["carry_over_phases"] = [s.strip() for s in args.carry.split(",")]

    save(path, data)
    print(f"close  {path}  completed={args.completed}  carry={data['carry_over_phases']}")


def cmd_score(args):
    path = latest_sprint_path()
    data = load(path)
    data["architect_scores"] = {
        "eval_reports_avg": args.eval_avg,
        "sprint_review":    args.review,
        "retro":            args.retro,
    }
    data["engineer_sprint_summary"] = {
        "plan_quality_avg":        args.plan_quality,
        "real_blockers":           args.blockers_real,
        "self_resolving_blockers": args.blockers_self,
    }
    if args.friction:
        data["engineer_sprint_summary"]["friction"] = args.friction
    save(path, data)
    print(f"score  {path}")


def cmd_archive_plan(args):
    src = "SPRINT_PLAN.md"
    if not os.path.exists(src):
        sys.exit(f"error: {src} not found")
    path = latest_sprint_path()
    data = load(path)
    n    = data.get("sprint", "X")
    d    = data.get("date", Date.today().isoformat())
    dst  = os.path.join(DATA_DIR, f"SPRINT_PLAN_{n}_{d}.md")
    os.rename(src, dst)
    print(f"archive-plan  {src} -> {dst}")


# ---------------------------------------------------------------------------
# State command
# ---------------------------------------------------------------------------

def cmd_state(args):
    op = args.operation

    # -- read ----------------------------------------------------------------
    if op == "read":
        data, warnings = state_load()
        emit(data, warnings)
        return

    # -- reset ---------------------------------------------------------------
    if op == "reset":
        if args.sprint is None:
            print("error: --reset requires --sprint N", file=sys.stderr)
            sys.exit(1)
        phases_raw = args.phases or ""
        phases = [s.strip() for s in phases_raw.split(",")] if phases_raw else []
        d = Date.today().isoformat()
        state = {
            "sprint":        args.sprint,
            "session":       f"SPRINT_{args.sprint}_{d}",
            "active_phase":  None,
            "phase_status":  {str(i+1): "pending" for i in range(len(phases))},
            "phase_names":   {str(i+1): name for i, name in enumerate(phases)},
            "tasks":         {},
            "team":          {"architect_id": None, "engineer_id": None},
            "open_blockers": [],
            "director_decisions": [],
        }
        ok, err = state_save(state)
        if ok:
            print(f"state reset  sprint={args.sprint}  phases={len(phases)}")
        else:
            print(f"error: state reset failed ({err})")
            sys.exit(1)
        return

    # All other operations: load first, warn but continue if stale/missing
    data, warnings = state_load()
    for w in warnings:
        print(w)

    if not data and op not in ("reset",):
        print("WARN: operating on empty state — results written but context may be incomplete")

    # -- set-phase -----------------------------------------------------------
    if op == "set-phase":
        if args.phase_id is None or args.status is None:
            sys.exit("error: set-phase requires --phase-id and --status")
        if args.status not in VALID_PHASE_STATUSES:
            sys.exit(f"error: invalid phase status '{args.status}' — valid: {VALID_PHASE_STATUSES}")
        phase_key = str(args.phase_id)
        data.setdefault("phase_status", {})[phase_key] = args.status
        if args.status == "active":
            data["active_phase"] = args.phase_id
        ok, err = state_save(data)
        if ok:
            print(f"state set-phase  phase={args.phase_id}  status={args.status}")
        else:
            print(f"WARN: state write failed ({err}) — phase status not persisted")

    # -- set-task ------------------------------------------------------------
    elif op == "set-task":
        if args.task_id is None or args.status is None:
            sys.exit("error: set-task requires --task-id and --status")
        if args.status not in VALID_TASK_STATUSES:
            sys.exit(f"error: invalid task status '{args.status}' — valid: {VALID_TASK_STATUSES}")
        data.setdefault("tasks", {})[args.task_id] = args.status
        ok, err = state_save(data)
        if ok:
            print(f"state set-task  task={args.task_id}  status={args.status}")
        else:
            print(f"WARN: state write failed ({err}) — task status not persisted")

    # -- set-team ------------------------------------------------------------
    elif op == "set-team":
        team = data.setdefault("team", {})
        if args.architect_id:
            team["architect_id"] = args.architect_id
        if args.engineer_id:
            team["engineer_id"] = args.engineer_id
        ok, err = state_save(data)
        if ok:
            print(f"state set-team  architect={team.get('architect_id')}  engineer={team.get('engineer_id')}")
        else:
            print(f"WARN: state write failed ({err}) — team IDs not persisted")

    # -- open-blocker --------------------------------------------------------
    elif op == "open-blocker":
        if not args.blocker_id or not args.description:
            sys.exit("error: open-blocker requires --blocker-id and --description")
        blockers = data.setdefault("open_blockers", [])
        existing = next((b for b in blockers if b.get("id") == args.blocker_id), None)
        if existing:
            print(f"WARN: blocker {args.blocker_id} already exists — use resolve-blocker or defer-blocker")
        else:
            entry = {
                "id":           args.blocker_id,
                "phase":        args.phase_id,
                "task":         args.task_id,
                "reported_by":  args.reported_by or "ENGINEER",
                "escalated_to": args.escalated_to or "ARCHITECT",
                "status":       "open",
                "description":  args.description,
                "opened_at":    datetime.now().isoformat(timespec="seconds"),
            }
            blockers.append(entry)
            ok, err = state_save(data)
            if ok:
                print(f"state open-blocker  id={args.blocker_id}")
            else:
                print(f"WARN: state write failed ({err}) — blocker not persisted, log manually to BLOCKERS.md")

    # -- resolve-blocker -----------------------------------------------------
    elif op == "resolve-blocker":
        if not args.blocker_id or not args.decision:
            sys.exit("error: resolve-blocker requires --blocker-id and --decision")
        blockers = data.get("open_blockers", [])
        entry = next((b for b in blockers if b.get("id") == args.blocker_id), None)
        if not entry:
            print(f"WARN: blocker {args.blocker_id} not found in state — may have been lost; log resolution manually to BLOCKERS.md")
        else:
            entry["status"]      = "resolved"
            entry["decision"]    = args.decision
            entry["reversible"]  = args.reversible
            entry["resolved_at"] = datetime.now().isoformat(timespec="seconds")
            data.setdefault("director_decisions", []).append({
                "phase":      entry.get("phase"),
                "task":       entry.get("task"),
                "blocker_id": args.blocker_id,
                "decision":   args.decision,
                "reversible": args.reversible,
                "decided_at": entry["resolved_at"],
            })
            ok, err = state_save(data)
            if ok:
                print(f"state resolve-blocker  id={args.blocker_id}  reversible={args.reversible}")
            else:
                print(f"WARN: state write failed ({err}) — resolution not persisted, log manually to BLOCKERS.md")

    # -- defer-blocker -------------------------------------------------------
    elif op == "defer-blocker":
        if not args.blocker_id or not args.reason:
            sys.exit("error: defer-blocker requires --blocker-id and --reason")
        blockers = data.get("open_blockers", [])
        entry = next((b for b in blockers if b.get("id") == args.blocker_id), None)
        if not entry:
            print(f"WARN: blocker {args.blocker_id} not found in state — log deferral manually to BLOCKERS.md")
        else:
            entry["status"]      = "deferred"
            entry["reason"]      = args.reason
            entry["deferred_at"] = datetime.now().isoformat(timespec="seconds")
            ok, err = state_save(data)
            if ok:
                print(f"state defer-blocker  id={args.blocker_id}")
            else:
                print(f"WARN: state write failed ({err}) — deferral not persisted, log manually to BLOCKERS.md")

    else:
        sys.exit(f"error: unknown state operation '{op}'")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    p = argparse.ArgumentParser(
        prog="sprint_data.py",
        description=__doc__,
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    # init
    pi = sub.add_parser("init", help="Create a new sprint data file and reset session state")
    pi.add_argument("--sprint",         type=int, required=True)
    pi.add_argument("--goal",                     required=True)
    pi.add_argument("--phases",                   required=True, help="Comma-separated phase names")
    pi.add_argument("--phases-planned", type=int, required=True, dest="phases_planned")
    pi.add_argument("--date",           default=None, help="YYYY-MM-DD (default: today)")

    # task
    pt = sub.add_parser("task", help="Add or update a task record in the latest sprint")
    pt.add_argument("--id",           type=int, required=True)
    pt.add_argument("--cycles",       type=int, default=None)
    pt.add_argument("--blockers",     type=int, default=None)
    pt.add_argument("--clarity",      type=int, default=None, metavar="1-5")
    pt.add_argument("--completeness", type=int, default=None, metavar="1-5")
    pt.add_argument("--friction",     default=None)
    pt.add_argument("--planning-note", action="store_true", dest="planning_note")
    pt.add_argument("--depends",      default=None, help="Comma-separated task IDs")
    pt.add_argument("--chars",        type=int, default=None)

    # metric
    pm = sub.add_parser("metric", help="Increment proxy metrics")
    pm.add_argument("--chars",       type=int, default=0)
    pm.add_argument("--invocations", type=int, default=1)
    pm.add_argument("--turns",       type=int, default=0)

    # close
    pc = sub.add_parser("close", help="Mark sprint complete and record duration")
    pc.add_argument("--completed", type=int, required=True)
    pc.add_argument("--carry",     default=None)

    # score
    ps = sub.add_parser("score", help="Record quality scores")
    ps.add_argument("--eval-avg",      type=float, required=True, dest="eval_avg",    metavar="1-5")
    ps.add_argument("--review",        type=float, required=True,                      metavar="1-5")
    ps.add_argument("--retro",         type=float, required=True,                      metavar="1-5")
    ps.add_argument("--plan-quality",  type=float, required=True, dest="plan_quality", metavar="1-5")
    ps.add_argument("--blockers-real", type=int,   required=True, dest="blockers_real")
    ps.add_argument("--blockers-self", type=int,   required=True, dest="blockers_self")
    ps.add_argument("--friction",      default=None)

    sub.add_parser("archive-plan",
                   help="Move SPRINT_PLAN.md to .claude/sprints-data/")

    # state
    pst = sub.add_parser("state", help="Read or mutate session state (SESSION_STATE.json)")
    pst.add_argument("operation", choices=[
        "read", "reset",
        "set-phase", "set-task", "set-team",
        "open-blocker", "resolve-blocker", "defer-blocker",
    ])
    pst.add_argument("--sprint",        type=int,   default=None, help="Required for reset")
    pst.add_argument("--phases",        default=None, help="Comma-separated phase names (for reset)")
    pst.add_argument("--phase-id",      type=int,   default=None, dest="phase_id")
    pst.add_argument("--task-id",       default=None, dest="task_id",
                     help="Phase-scoped task ID, e.g. '2-3' (phase 2, task 3)")
    pst.add_argument("--status",        default=None)
    pst.add_argument("--architect-id",  default=None, dest="architect_id")
    pst.add_argument("--engineer-id",   default=None, dest="engineer_id")
    pst.add_argument("--blocker-id",    default=None, dest="blocker_id")
    pst.add_argument("--description",   default=None)
    pst.add_argument("--reported-by",   default=None, dest="reported_by")
    pst.add_argument("--escalated-to",  default=None, dest="escalated_to")
    pst.add_argument("--decision",      default=None)
    pst.add_argument("--reversible",    action="store_true", default=False)
    pst.add_argument("--reason",        default=None)

    args = p.parse_args()
    {
        "init":         cmd_init,
        "task":         cmd_task,
        "metric":       cmd_metric,
        "close":        cmd_close,
        "score":        cmd_score,
        "archive-plan": cmd_archive_plan,
        "state":        cmd_state,
    }[args.cmd](args)


if __name__ == "__main__":
    main()
