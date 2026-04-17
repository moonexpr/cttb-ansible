#!/usr/bin/env bash
# Sprint artifact validation. Run from repo root after sprint close.
set -euo pipefail

PASS=0
FAIL=0

check_pass() { printf '\033[1;32m  ✓ %s\033[0m\n' "$1"; ((PASS++)); }
check_fail() { printf '\033[1;31m  ✗ %s — %s\033[0m\n' "$1" "$2"; ((FAIL++)); }

echo "Sprint Eval"
echo "==========="

# SPRINT_PLAN.md must be absent from root (archived to .claude/sprints-data/)
if [[ -f "SPRINT_PLAN.md" ]]; then
  check_fail "SPRINT_PLAN.md archived" "file still at root — run: python3 .claude/sprint/tools/sprint_data.py archive-plan"
else
  archived=$(ls .claude/sprints-data/SPRINT_PLAN_*.md 2>/dev/null | head -1 || true)
  if [[ -n "$archived" ]]; then
    check_pass "SPRINT_PLAN.md archived ($archived)"
  else
    check_fail "SPRINT_PLAN.md archived" "not at root but no SPRINT_PLAN_*.md found in .claude/sprints-data/"
  fi
fi

# DIRECTOR_JOURNAL.md must exist
if [[ -f ".claude/sprint/DIRECTOR_JOURNAL.md" ]]; then
  check_pass ".claude/sprint/DIRECTOR_JOURNAL.md present"
else
  check_fail ".claude/sprint/DIRECTOR_JOURNAL.md present" "file missing"
fi

# Data directory must exist
if [[ -d ".claude/sprints-data" ]]; then
  check_pass ".claude/sprints-data/ present"
else
  check_fail ".claude/sprints-data/ present" "directory missing"
fi

# At least one sprint JSON must exist and be valid
latest=$(ls -t .claude/sprints-data/SPRINT_*.json 2>/dev/null | head -1 || true)
if [[ -z "$latest" ]]; then
  check_fail "Sprint JSON present" "no SPRINT_*.json found in .claude/sprints-data/"
else
  check_pass "Sprint JSON present ($latest)"

  python3 - "$latest" <<'PYEOF'
import json, sys

path = sys.argv[1]

def ok(msg):
    print(f"\033[1;32m  ✓ {msg}\033[0m");
def fail(msg, reason):
    print(f"\033[1;31m  ✗ {msg} — {reason}\033[0m")

try:
    with open(path) as f:
        d = json.load(f)
    ok("Sprint JSON valid")
except json.JSONDecodeError as e:
    fail("Sprint JSON valid", str(e))
    sys.exit(1)

required = [
    ("sprint", None),
    ("date", None),
    ("phases_planned", "points_committed"),
    ("phases_completed", "points_completed"),
]
for primary, fallback in required:
    if primary in d:
        ok(f"JSON field '{primary}' present")
    elif fallback and fallback in d:
        ok(f"JSON field '{fallback}' present (legacy)")
    else:
        fail(f"JSON field '{primary}' present", "missing")

if "actual_tokens" in d:
    ok("Token data present (analyzed)")
elif "proxy_metrics" in d:
    ok("Proxy metrics present (run sprint_analyze.sh for actual tokens)")
else:
    fail("Metrics present", "neither actual_tokens nor proxy_metrics found")
PYEOF
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
