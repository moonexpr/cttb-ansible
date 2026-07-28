#!/usr/bin/env bash
# Group the diff between two refs by area, and list the PRs merged in that span.
#
# Usage:  release-scope.sh <previous-tag> [<head-ref>]
# e.g.    release-scope.sh sudhanix26.1.0 main
#
# Exists so release scope is COMPUTED rather than recalled. Reading `git log`
# by eye reliably misses whole subsystems in a release this size.
set -euo pipefail

FROM="${1:-}"
TO="${2:-main}"

[ -n "$FROM" ] || { echo "usage: $0 <previous-tag> [<head-ref>]" >&2; exit 2; }
git rev-parse -q --verify "$FROM" >/dev/null || { echo "error: no such ref: $FROM" >&2; exit 2; }
git rev-parse -q --verify "$TO"   >/dev/null || { echo "error: no such ref: $TO" >&2; exit 2; }

NUMSTAT=$(mktemp)
trap 'rm -f "$NUMSTAT"' EXIT
git diff --numstat "$FROM..$TO" > "$NUMSTAT"

echo "=== $FROM -> $TO ==="
echo "commits: $(git rev-list --count "$FROM..$TO")"
echo

echo "=== changes by area ==="
SCOPE_INPUT="$NUMSTAT" python3 <<'PY'
import os, collections

# Order matters: first match wins, most specific first.
RULES = [
    ("roles/mediawiki/files/skins/", "mediawiki skins"),
    ("roles/mediawiki",              "mediawiki role"),
    (".claude/skills",               ".claude/skills"),
    (".claude/sysadmin",             ".claude/sysadmin"),
    (".claude/release-notes",        ".claude/release-notes"),
    (".claude",                      ".claude (other)"),
    ("docs/",                        "docs/"),
    ("plays/",                       "plays/"),
    ("group_vars/",                  "group_vars/"),
    ("host_vars/",                   "host_vars/"),
    ("inventory/",                   "inventory/"),
    ("utils/",                       "utils/"),
]


def bucket(path):
    for prefix, name in RULES:
        if path.startswith(prefix):
            return name
    if path.startswith("roles/"):
        parts = path.split("/")
        return "roles/" + parts[1] if len(parts) > 1 else "roles/"
    return "repo root" if "/" not in path else path.split("/")[0] + "/"


lines, files = collections.Counter(), collections.Counter()
with open(os.environ["SCOPE_INPUT"]) as fh:
    for raw in fh:
        cols = raw.split("\t")
        if len(cols) < 3:
            continue
        add, dele, path = cols[0], cols[1], cols[2].strip()
        n = (int(add) if add.isdigit() else 0) + (int(dele) if dele.isdigit() else 0)
        k = bucket(path)
        lines[k] += n
        files[k] += 1

print("{:<34} {:>6} {:>8}".format("area", "files", "lines"))
print("-" * 50)
for k, v in lines.most_common():
    print("{:<34} {:>6} {:>8}".format(k, files[k], v))
print("-" * 50)
print("{:<34} {:>6} {:>8}".format("TOTAL", sum(files.values()), sum(lines.values())))
PY

echo
echo "=== root-level files touched ==="
git diff --name-only "$FROM..$TO" | grep -v '/' | sed 's/^/  /' || echo "  (none)"

echo
echo "=== PRs referenced in range ==="
git log --oneline "$FROM..$TO" | grep -oE '\(#[0-9]+\)' | tr -d '()#' | sort -un \
  | sed 's/^/  PR #/' || echo "  (none)"

echo
echo "=== reminder ==="
echo "  Read the PR bodies for the WHY:  gh pr view <n>"
echo "  Commit subjects say what moved; PR bodies say what it was for."
