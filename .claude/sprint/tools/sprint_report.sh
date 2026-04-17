#!/usr/bin/env bash
# Sprint metrics report. Run from repo root.
set -euo pipefail

DATA_DIR=".claude/sprints-data"

if [[ ! -d "$DATA_DIR" ]]; then
  echo "No sprint data at $DATA_DIR — run sprint_install.sh first."
  exit 1
fi

python3 - "$DATA_DIR" <<'PYEOF'
import json, os, sys, glob

data_dir = sys.argv[1]
files = sorted(glob.glob(os.path.join(data_dir, "SPRINT_*.json")))

if not files:
    print("No sprint data files found.")
    sys.exit(0)

sprints = []
for f in files:
    with open(f) as fh:
        try:
            sprints.append(json.load(fh))
        except json.JSONDecodeError:
            print(f"Warning: skipping malformed {f}")

sprints.sort(key=lambda d: d.get("sprint", 0))

# -- Per-sprint table --------------------------------------------------------
print("Sprint Report")
print("=" * 72)
print()
print(f"{'#':<5} {'Date':<12} {'Planned':>8} {'Done':>6} {'Dur(m)':>7} {'Carry':>6} {'Cycles':>7}")
print("-" * 72)

for d in sprints:
    n       = d.get("sprint", "?")
    date    = d.get("date", "?")
    planned = d.get("phases_planned") or d.get("points_committed") or 0
    done    = d.get("phases_completed") or d.get("points_completed") or 0
    dur     = d.get("duration_minutes", "?")
    carry   = len(d.get("carry_over_phases", d.get("carry_overs", [])))
    tasks   = d.get("tasks", [])
    cycles  = sum(t.get("cycles", 1) for t in tasks) if tasks else "?"
    print(f"{n:<5} {date:<12} {planned:>8} {done:>6} {str(dur):>7} {carry:>6} {str(cycles):>7}")

# -- Latest sprint detail ----------------------------------------------------
latest = sprints[-1]
print()
print(f"Latest: Sprint {latest.get('sprint','?')} — {latest.get('date','?')}")
goal = latest.get("goal") or latest.get("sprint_goal")
if goal:
    print(f"  Goal: {goal}")

# Token data
actual = latest.get("actual_tokens")
proxy  = latest.get("proxy_metrics", {})

if actual:
    inp   = actual.get("input_tokens", 0)
    out   = actual.get("output_tokens", 0)
    cache = actual.get("cache_read_input_tokens", 0)
    total = actual.get("total_tokens", 0)
    print(f"  Tokens (actual)  — input: {inp:,}  output: {out:,}  "
          f"cache_read: {cache:,}  total: {total:,}")
else:
    print("  Tokens (actual)  — not yet analyzed  (run .claude/sprint/tools/sprint_analyze.sh)")

if proxy:
    chars = proxy.get("context_chars_total", 0)
    est   = chars // 4
    inv   = proxy.get("invocation_count", "?")
    turns = proxy.get("agent_turns_total", "?")
    print(f"  Tokens (proxy)   — context_chars: {chars:,}  (~{est:,} est.)  "
          f"invocations: {inv}  total_turns: {turns}")

# Quality scores
arch  = latest.get("architect_scores", {})
eng   = latest.get("engineer_sprint_summary", {})
if arch:
    avg_eval = arch.get("eval_reports_avg", "?")
    review   = arch.get("sprint_review", "?")
    retro    = arch.get("retro", "?")
    print(f"  Architect scores — eval_avg: {avg_eval}/5  review: {review}/5  retro: {retro}/5")
if eng:
    pq    = eng.get("plan_quality_avg", "?")
    real  = eng.get("real_blockers", "?")
    selfc = eng.get("self_resolving_blockers", "?")
    print(f"  Engineer summary — plan_quality: {pq}/5  blockers real: {real}  self-resolved: {selfc}")
PYEOF
