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

Every release also carries a **title**, E.g. `Accessible Credential Handling`.
Pick it after writing the Rationale, when the theme is visible, rather than
before.

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

4. **Write `.claude/release-notes/<tag>.md`** in the canonical structure below.

## Canonical structure

Every release note uses these sections, in this order. The shape is fixed so a
reader can skim any release the same way; omit a section only when it is
genuinely empty.

```markdown
# Sudhanix <version> — <Release Title>

Released <date>. Previous release: [`<prev-tag>`](<url>) (<date>).

<One paragraph. What this release is about, and explicitly whether the
deployed image changes. Sysadmins read that sentence to decide whether a
fleet run is needed.>

---

## Highlights
<5–8 bullets. Bold lead-in naming the change, then one clause of what it
means. This is the skim layer; a reader who stops here should still know
what shipped.>

> **Action required:** <only when a sysadmin must do something by hand.>

---

## Changelog
<Flat bullets, one per change, technical and specific. File and role names,
counts, what was deleted. No rationale here — this is the record.>

---

## Rationale
<### subsections, one per substantive area. Each opens on the problem, then
the fix, then what it costs the reader. This is where the prose lives.>

---

## What this asks of you
<Numbered, runnable steps. State plainly when there is nothing to deploy.>

## Known issues
<Issue links. Distinguish pre-existing defects from anything introduced here.>

## Merged
<PR links.>
```

**Give every release a title.** `Sudhanix 26.1.1 — Accessible Credential
Handling`. Name the theme the work turned out to be about, not the largest
diff. The title goes in the `# ` heading, the GitHub Release name, and the
first line of the tag annotation, and all three must agree.

**Highlights and Changelog are different jobs.** Highlights is what a reader
tells a colleague; Changelog is what a reader greps six months later. A bullet
that appears in both is written differently in each.

**Rationale is where the release earns attention.** Explain the failure someone
would have hit. "The error names the failing task, never the missing
collection" is useful; "added requirements.yml" belongs in the Changelog.

5. **Commit the notes** to `main` on their own, separate from feature work.

6. **Tag, annotated,** with a condensed summary that ends by pointing at the
   notes file — matching `sudhanix26.1.0`'s style:

   ```bash
   git -c gpg.program=gpg-loopback tag -a -s <tag> -F <message-file>
   git push origin main
   git push origin <tag>
   ```

7. **Publish the GitHub Release** from the same notes so the web view and the
   repo never disagree. The release name carries the title:

   ```bash
   gh release create <tag> --title "Sudhanix <version> — <Release Title>" \
       --notes-file .claude/release-notes/<tag>.md --latest
   ```

   To retitle an already-published release, `gh release edit <tag> --title
   "..."`. The tag annotation cannot be corrected the same way; rewriting a
   pushed tag breaks every clone that already fetched it, so a title fixed
   after tagging lives in the Release and the notes, and the annotation is
   left alone.

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
