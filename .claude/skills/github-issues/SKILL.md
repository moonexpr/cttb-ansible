---
name: github-issues
user-invocable: true
argument-hint: "<the defect / task / missing feature to file>"
description: >
  File one actionable item against moonexpr/cttb-ansible the
  agent-pickup way — dedup, create with the prescribed body sections
  and priority label, then categorize (milestone + sub-issue /
  blocked-by) in the same pass — using the `gh` CLI and the GitHub
  Issues v2 API. Triggers on `/github-issues <thing>`, "file an
  issue", "open a bug", "track this as a task", a side issue
  discovered mid-development, or `/document` routing an actionable
  artifact here. Encapsulates the CLAUDE.md "Issue Filing" protocol
  so callers stop inlining it. One job: a single, navigable issue.
---

## When to apply

Apply for exactly one fileable item: a reproducible non-user-error
failure, an advertised capability that doesn't match behavior, a
workaround whose underlying problem lives in this repo, or a
likely-stale/contradictory piece of code/config/doc whose fix is
non-trivial. Do **not** apply for the thing currently being fixed
(that's the task, not a side issue), stylistic nits, speculative
refactors, items already covered by an open issue, or a learned
preference that belongs in `MEMORY.md`. Filing here is the standing
authorization from `CLAUDE.md` — do not pause to ask; file and resume.

`CLAUDE.md` → **"Issue Filing (Don't Block Development)"** is the
policy source of truth for body shape, priority taxonomy, and
relationship semantics. This skill is its executable form; if the two
ever diverge, `CLAUDE.md` wins on policy and this skill is updated to
match.

## Procedure

1. **Dedup.** Match on the affected tool/path, not just title words:

   ```bash
   gh issue list -R moonexpr/cttb-ansible --search "<keyword>" --state all
   git -C . log --oneline | grep -i "gh-<n>\|#<n>"   # fix may have landed unclosed
   ```

   If an open or recently-fixed issue already covers it, stop and
   report that issue instead of filing a duplicate.

2. **File** with the body sections in this exact order (from
   `CLAUDE.md`): **Repro** (exact commands + error) · **Expected** ·
   **Actual** (failure signature verbatim) · **Repo locations**
   (absolute paths) · **Acceptance criteria** (testable checkboxes) ·
   **Workaround** (copy-pasteable, if any) · **Where to look first**
   (likely faulty file/function/flag) · **Context** (one short
   paragraph: when/where discovered, why it mattered). Write the body
   to a file under the working tree (never `/tmp`) and pass it:

   ```bash
   gh issue create -R moonexpr/cttb-ansible \
     --title "<area>: <one-line behavioral description>" \
     --label <Blocker|Release|Unscheduled> \
     --body-file <path>
   ```

   Priority taxonomy: `Blocker` (stops mass rollout), `Release`
   (must-fix for a clean cut), `Unscheduled` (nice-to-have), or no
   label if none fits.

3. **Categorize in the same pass** (uncategorized issues drift to the
   bottom of every triage view — do not defer this):

   a. **Milestone** — match the area of work, not urgency:

   ```bash
   gh api repos/moonexpr/cttb-ansible/milestones --jq '.[] | "\(.number) \(.title)"'
   gh issue edit <n> -R moonexpr/cttb-ansible --milestone "<title>"
   ```

   Guide: PXE/installer → `P1 Autoinstaller`; desktop/session/branding
   → `P2a Bootstrap & Migration`; vajra → `P2b Vajra Multitool`; wiki
   content/theme → `SP Wiki Upgrade`.

   b. **Relationships** (always send
   `-H "X-GitHub-Api-Version: 2022-11-28"`). Pick **sub-issue** when
   the relationship is structural (parent decomposes into children);
   **blocked-by** when temporal (X must land before Y can be verified):

   ```bash
   # sub-issue (parent ← child)
   CHILD_ID=$(gh api repos/moonexpr/cttb-ansible/issues/<child> --jq .id)
   gh api -X POST "repos/moonexpr/cttb-ansible/issues/<parent>/sub_issues" \
     -F "sub_issue_id=$CHILD_ID" -H "X-GitHub-Api-Version: 2022-11-28"

   # blocked-by dependency
   BLOCKER_ID=$(gh api repos/moonexpr/cttb-ansible/issues/<blocker> --jq .id)
   gh api -X POST "repos/moonexpr/cttb-ansible/issues/<blocked>/dependencies/blocked_by" \
     -F "issue_id=$BLOCKER_ID" -H "X-GitHub-Api-Version: 2022-11-28"
   ```

   A bare `#N` mention in the body is enough for "related, but neither
   structural nor blocking". The dependency call's consistency is
   eventual — re-`GET` if verifying immediately.

4. **Resume.** Drop the issue URL into the running task summary and
   continue the original work in the same turn. Do not switch to
   fixing the filed issue unless the user asks. Filing one navigable
   issue is the whole job.

## Resources

Self-contained. Drives the `gh` CLI and the GitHub Issues v2 API
(`gh api`); auth is the ambient `gh` login. No new scripts, no sibling
files. The canonical policy lives in this repo's `CLAUDE.md`
("Issue Filing") and is intentionally not duplicated beyond the
operational steps above.
