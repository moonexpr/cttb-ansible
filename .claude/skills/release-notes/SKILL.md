---
name: release-notes
user-invocable: true
argument-hint: "<version-tag>  e.g. sudhanix26.1.2"
description: >
  Cut a Sudhanix release: determine the scope since the previous tag, write
  `.claude/release-notes/<tag>.md`, commit it, create the annotated git tag,
  push, publish the GitHub Release, and optionally draft an announcement email
  to the sysadmin list. Triggers on `/release-notes <tag>`, "cut a release",
  "tag a release", "bump the version and write release notes", "draft the
  release announcement", or a merge that completes a release milestone. One
  job: turn merged work into a tagged, documented, announced release.
---

## When to apply

Apply when work merged to `main` should become a named release. Do **not**
apply for an ordinary merge, a hotfix that nobody needs to be told about, or
to re-tag an existing version — retagging a published release rewrites history
that others may have fetched.

## Versioning

Tags are `sudhanix<OS-release>.<minor>.<patch>` — e.g. `sudhanix26.1.1`. The
leading number tracks the **OS generation** (`sudhanix_release` in
`roles/common/defaults/main.yml`), not semver's major. It changes only on a
new Ubuntu base.

- **minor** — new capability, changed workflow, anything a sysadmin must act on.
- **patch** — fixes, docs, tooling; no action required of the fleet.

Confirm the intended number with the operator when it is ambiguous; do not
infer a bump level from the diff size alone.

## Procedure

1. **Establish the baseline.** Find the previous tag and confirm the new one
   is free. Tags in this repo are **annotated**, never lightweight.

   ```bash
   git fetch --tags origin
   git tag --sort=-v:refname | head -5
   git rev-parse -q --verify refs/tags/<new-tag> && echo "ALREADY EXISTS - stop"
   ```

2. **Confirm `main` is current and clean.**

   ```bash
   git checkout main && git merge --ff-only origin/main
   git status --short
   ```

   Never tag a dirty tree or a branch behind its remote.

3. **Derive the scope — do not eyeball the log.** Group the diff by area so
   the notes describe what actually changed rather than what you remember
   changing:

   ```bash
   bash .claude/skills/release-notes/scripts/release-scope.sh <previous-tag> main
   ```

   Read the merged PR bodies for the *why* behind each area
   (`gh pr list --state merged --limit 20`). The commit subjects tell you what
   moved; the PR bodies tell you what it was for.

4. **Write `.claude/release-notes/<tag>.md`.** Prose, not a changelog dump —
   see **Voice** below. Cover, in this order, omitting any section with
   nothing to say:

   - One-paragraph summary, and explicitly whether the **deployed image
     changes**. Sysadmins read that first to decide whether a fleet run is needed.
   - One `##` section per substantive area, each explaining the problem before
     the fix.
   - `## Upgrading` — numbered, runnable steps. State plainly if there is
     nothing to deploy.
   - `## Known issues` — with issue links. Distinguish pre-existing defects
     from anything this release introduces.
   - `## Merged` — PR links.

   Call out **action required** in a blockquote wherever a sysadmin must do
   something manually, such as storing a new credential.

5. **Commit the notes** to `main` on their own, separate from feature work.

6. **Tag, annotated,** with a condensed summary that ends by pointing at the
   notes file — matching `sudhanix26.1.0`'s style:

   ```bash
   git -c gpg.program=gpg-loopback tag -a -s <tag> -F <message-file>
   git push origin main
   git push origin <tag>
   ```

7. **Publish the GitHub Release** from the same notes so the web view and the
   repo never disagree:

   ```bash
   gh release create <tag> --title "Sudhanix <version>" \
       --notes-file .claude/release-notes/<tag>.md --latest
   ```

8. **Announce, if asked.** Draft to `.claude/artifacts/`, never send
   unprompted — see **Announcement drafts**.

## Voice

Write the way `/wiki-author` does: connected prose a colleague can read
start to finish, not a bullet list of commit subjects. Lead each section with
the problem, then the fix, then what it costs the reader.

Concretely:

- **Explain the failure a reader would have hit.** "The error names the failing
  task, never the missing collection" is useful; "added requirements.yml" is not.
- **Name what is *not* affected.** "No change to the deployed image" saves
  everyone a fleet run.
- **Surface limits honestly.** If a change does not revoke, or does not cover
  reimaged hosts, say so with an issue link rather than letting someone find
  out later.
- **No session links, no co-author trailers**, in notes, tags, or commits.
- **Respect the disclosure line.** Release notes are published publicly on a
  public repo and emailed outside it. Describe *what a sysadmin must do*; do
  not spell out credential blast radius, trust relationships between secrets,
  or anything that reads as a roadmap of where the network is weak. When a
  security-relevant change needs explaining, say what to do, not what breaks
  if you don't. Ask the operator when unsure.

## Announcement drafts

When the operator asks for an announcement, write it to
`.claude/artifacts/release-announcement-<tag>.md` — a complete email with
`To:`, `Subject:`, body, and sign-off — and hand back the path. It is a
**draft**: report it, do not send it, and do not wire it into a mail tool
unless explicitly told to.

Keep it much shorter than the notes. Recipients want: what shipped, whether
they must do anything, and where to read more. Link the release; do not
restate it.

If the operator names a sign-off that is not their own, use it as given, and
say plainly in your summary which name you signed — never send under another
person's name without a clear instruction to do so.

## Resources

- `scripts/release-scope.sh` — groups the diff between two refs by area and
  lists merged PRs. Run in step 3; it exists so the scope is computed, not
  recalled.
- `.claude/release-notes/` — published notes, one file per tag. This directory
  is the source of truth; the GitHub Release and the tag annotation are both
  derived from it.
