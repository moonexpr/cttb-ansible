---
name: wiki-author
user-invocable: true
description: >
  CTTB wiki (wiki.cttb, MediaWiki 1.43) authoring workflow. Triggers when
  drafting, editing, deleting, or styling pages on wiki.cttb, when working
  with Mbox/Ambox templates, when adding to MediaWiki: system messages,
  when wiring up Lockdown protection, or when following wiki edits up with
  cache purges. Drafts live in `.claude/wiki-pages/`; the API tooling
  lives in `utils/`. The skill also sets the authorial voice:
  write like a professor drafting a textbook chapter — connected prose,
  figures with captions, footnoted references, and templates that scale
  across a category — rather than a punch-list of bullet points.
---

## When to apply

Use this skill whenever writing to `wiki.cttb` — new pages, page edits,
file uploads, system-message overrides (`MediaWiki:Common.css`,
`MediaWiki:Sitenotice`, `MediaWiki:Loginreqpagetext`, etc.), template
imports, or deletions. Do not apply for desktop Sudhanix work, role
edits unrelated to the `mediawiki` role, or anything that doesn't touch
the wiki database.

The wiki currently runs MediaWiki 1.43.8 on Ubuntu 24.04 in container
`wiki-2404` at `10.11.1.34`. Lockdown gates five admin namespaces
(`IT`, `DRBU`, `DVGS`, `DVBS`, `CTTB`) by user group.

Always read **WIKISTYLE.md** alongside this skill — it carries the
Wikipedia Manual-of-Style rules (lead-sentence shape, sentence-case
headings, capitalisation, code formatting, See-also conventions,
anti-patterns) that apply on top of the project-specific guidance
below. When the two ever conflict, WIKISTYLE wins on structure;
this skill wins on voice and on CTTB-specific conventions.

---

## Voice — write like a textbook chapter

The strongest pages on this wiki read like a chapter from a sysadmin
textbook written by someone who has run the system for years. Aim for:

- **Connected prose over bulleted punch-lists.** A paragraph that
  builds a mental model is almost always better than three bullets that
  state isolated facts. Bullets are appropriate for genuinely parallel
  items (a list of files, a sequence of commands, a table of options),
  not for the body of an explanation. Default to paragraphs.
- **Narrative arc.** Open with what the system *is* and what problem it
  solves, walk through how it works in enough depth that a reader can
  reason about it, then close with the operational reality — what
  breaks, what's been deferred, where the bodies are buried. Don't
  start with the commands.
- **Confidence without bravado.** State things plainly. The system was
  chosen because of X. The trade-off is Y. The known wart is Z. No
  "powerful," "elegant," "robust" filler — those are reader's job to
  decide. (See WIKISTYLE §3 on encyclopedic voice.)
- **Attributed history when it matters.** "Rui set up the original
  reprepro mirror in 2018; the move to a chrooted snapshot tree in
  2024 was prompted by …" Names and dates anchor the reader and make
  the page maintainable.
- **Treat the reader as a peer.** Not a beginner who needs hand-holding,
  not an expert who can decode jargon. Expand acronyms on first use
  (WIKISTYLE §5), define the one term per page that isn't obvious, and
  trust the rest.

The Wikipedia anti-patterns in WIKISTYLE §13 — "click here," "note
that," title-case headings, lead bullet lists — apply verbatim. Drop
"You'll want to," "Just run," "It should be noted." State the fact.

---

## Section hierarchy — nest, don't flatten

A wiki page with more than ~6 level-2 (`==`) sections needs a
hierarchical TOC, not a flat scroll. The reader should be able to
glance at the table of contents and immediately see the page's
major parts; expanding a part reveals its sub-tasks; expanding a
sub-task reveals its detail. A flat list of fifteen peer headers
defeats the TOC's purpose — it becomes search-by-skim instead of
navigation by structure.

The pattern to apply (validated on the LDAP article, 2026-05-06):

- **Top-level (`==`) clusters by audience intent.** Examples:
  "Architecture and data model" (concepts), "Linux client integration"
  (subsystem deep-dive), "Exploring the directory anonymously"
  (user task), "Sysadmin operations" (admin tasks). Three to five
  parents is comfortable; one parent per major reader use-case.
- **Each parent gets a one- or two-sentence intro paragraph
  immediately after the header.** It states what's inside and why
  someone would expand it. Without this, the parent is a label;
  with it, the parent helps the reader decide whether to read on.
- **Second-level (`===`) groupings within a parent split by
  sub-task family.** Inside Sysadmin operations, for instance:
  "User account lifecycle", "Password and access management",
  "Backup and configuration", "Day-to-day querying". Two to four
  groups per parent; if you only have one group's worth of content,
  the parent isn't earning its keep — flatten it.
- **Individual items at `====` (level 4); their internal
  subsections at `=====` (level 5).** MediaWiki renders all six
  levels, but past `=====` the visual hierarchy gets weak; if you
  need a sixth level, you probably want to merge.

Apply this when authoring a new page or revisiting an existing
one whose TOC has gone flat. The pre-publish checklist below now
includes a "TOC sanity check" — count the `==` headers and ask
whether they'd benefit from clustering.

---

## Figures and diagrams

A good page on this wiki has at least one figure. Architecture
diagrams, data-flow arrows, network topologies, package-pipeline
flows, decision trees — anything that compresses a paragraph of prose
into a glance.

Generate figures alongside the prose, not after. The convention:

- **Author the diagram in SVG.** Hand-rolled SVG is fine for boxes and
  arrows; for anything organic use Graphviz / D2 / Mermaid → SVG, or
  draw in Excalidraw and export. Keep the source (`.dot`, `.d2`, the
  Excalidraw `.excalidraw` JSON, etc.) somewhere recoverable — drop
  it next to the SVG in `.claude/wiki-pages/` or under
  `roles/<role>/files/diagrams/`.
- **Also produce a PNG fallback** at 2× the intended display width.
  Some skins and the printable view render PNGs more reliably than
  SVGs.
- **Upload both.** `utils/wiki upload /path/to/foo-architecture.svg "description"`
  and the same for the `.png`.
- **Embed with `[[File:Foo-architecture.svg|thumb|right|400px|<caption>]]`**
  so the image renders inside a thumbnail frame with a caption. Bare
  `[[File:Foo.svg]]` gives a full-bleed unboxed image — almost never
  what you want (WIKISTYLE quick checklist).
- **Caption every figure.** The caption should make the figure
  meaningful on its own — if a reader skims and only reads captions,
  they should still get the gist.

ASCII diagrams are an acceptable last resort and read well in `<pre>`
blocks for simple flows (boot order, message-passing). Prefer real
SVG for anything with more than five nodes or any non-orthogonal
relationships.

---

## Footnotes and references

Treat outside sources the way a textbook does — cited inline so the
reader can verify, with a References section at the bottom.

Use Wikipedia's `<ref>` mechanism (now available — the Cite extension
is bundled with MediaWiki 1.43 and was enabled during the migration):

```
…uses the [[STARTTLS]] command to upgrade the connection in place.<ref>RFC 4511 §4.14, "StartTLS Operation."</ref>

== References ==
<references />
```

For sources cited more than once:

```
…relies on the standard SSSD configuration<ref name="sssd-arch">[https://sssd.io/design-pages/active_directory_provider.html SSSD Active Directory provider design].</ref> …
…the same caching layer<ref name="sssd-arch" /> also …
```

Conventions:

- **Cite RFCs by number and section** when the section makes the claim
  precise: `RFC 5321 §4.5.3`. Short and unambiguous.
- **Cite vendor docs by URL + page title.** Don't cite a generic site
  homepage for a specific claim.
- **Cite man pages by name and section**: `sshd_config(5)`,
  `systemd.service(5)`. The reader can run `man 5 sshd_config` and
  verify locally.
- **Cite the cttb-ansible repo** for any claim that depends on our
  configuration: a path like `roles/openldap-server/templates/slapd.conf.j2`
  is a perfectly good footnote.
- **Glossary footnotes** (`<ref>'''Term:''' definition.</ref>`) are
  useful for a one-line aside that would derail the prose.

Do not paste large external blockquotes — summarise and cite. Anything
copied verbatim must be license-compatible (CC-BY-SA or compatible
public-domain / RFC 5378 IETF text).

---

## Templates for category-scale documentation

When a category will host many similar pages — the IT-namespace
infrastructure pages, the per-host runbooks, the per-service
operations sheets — write a wikitext template once and reuse it.
Templates keep similar pages structurally identical, which is
worth more than any individual page's polish.

The pattern:

1. Decide the shape of one canonical page in the category (e.g. an
   "Operations sheet" with sections: Purpose, Architecture, Common
   tasks, Failure modes, On-call notes, References).
2. Write the page itself first to validate the shape.
3. Lift the structure into `Template:OperationsSheet` (or whatever
   the category needs). Templates accept named parameters with
   `{{{purpose|}}}`, `{{{architecture|}}}`, etc., and can ship their
   own TemplateStyles via `<templatestyles src="Template:OperationsSheet/styles.css"/>`.
4. Refactor the original page to use the template.
5. Document the template on its `/doc` subpage with a parameter
   table and a usage example. Categorise it under
   `[[Category:Templates]]` and a content category.

A few templates already exist on this wiki (`{{IT Infrastructure}}`,
`{{Quotation}}`, the imported Wikipedia message-box family). Match
their style — small, named parameters, sensible defaults — rather
than inventing new conventions.

For *content* templates that wrap formatting around an inline phrase
(`{{Note|…}}`, `{{Warning|…}}`), prefer the corresponding `cttb-note`
/ `cttb-warning` CSS class with a div, since those are already in
`MediaWiki:Common.css` and don't require a transclusion round-trip.

---

## Workflow

Drafts always live in `.claude/wiki-pages/`. Filename convention: page
title with spaces and `:` replaced by `_` — `IT:Sudhanix` →
`IT_Sudhanix.txt`, `MediaWiki:Common.css` → `MediaWiki_Common.css`.
Diagram sources (`.svg`, `.dot`, `.d2`, `.excalidraw`) live alongside
their published `.png` exports in the same directory. Never write
drafts to `/tmp/`; the wiki-pages directory is gitignored and
persists across sessions.

All wiki I/O goes through the unified `utils/wiki` CLI —
**never hand-roll `curl`/`wget` against `wiki.cttb`**, in Bash or inside
the `ctx_*` sandbox (the think-in-code hook denies both). If the CLI is
missing a capability, extend it (`wiki_lib.py`) per the
script-persistence rule; the next agent inherits the subcommand instead
of re-improvising HTTP. Auth is handled per-command — there is no
separate login step. The standard cycle:

```bash
# 0. When revising an existing page, see who touched it last and why
utils/wiki history "Page Title" -n 5 --login

# 1. Pull current wikitext into .claude/wiki-pages/ (creates it if missing)
utils/wiki get "Page Title"

# 2. Edit the local draft with Edit/Write
# 3. Push back
utils/wiki edit "Page Title" .claude/wiki-pages/Page_Title.txt "edit summary"

# 4. Purge the parser cache so the next viewer sees the new render (API-based)
utils/wiki purge "Page Title"
```

- Files: `utils/wiki upload .claude/wiki-pages/file.svg "description"`.
- Sitenotice: `utils/wiki sitenotice .claude/wiki-pages/wiki-sitenotice.txt`
  (or `wiki push-notice` for sitenotice + Common.js together).
- After a `Template:` edit, purge with `--force` to run forcelinkupdate:
  `utils/wiki purge --force "Template:Foo"`.
- Deletion (sysop): `utils/wiki delete "Page Title" "reason"`.
- Need a shell on the wiki container (maintenance scripts, DB checks)?
  That is **not** this skill's job — use `/cttb-host` (`cttb-ct.sh
  shell wiki`) or `utils/wiki maint <subcommand>` for
  `maintenance/run.php`. Do not hand-roll the `ssh … ProxyJump=srv-vm`
  chain here.

---

## Wikitext rules that bite

- **Template literals in body text need `<nowiki>`**. `<code>{{Ambox}}</code>`
  still transcludes the template inside the `<code>` tag. Wrap with
  `<nowiki>`: `<code><nowiki>{{Ambox}}</nowiki></code>`. Same for any
  `[[…]]` you want to display literally.
- **Mbox templates have no `title` parameter**. Put the heading inline as
  bold: `text = '''Audience controlled content.''' Body…`.
- **Page text inside `MediaWiki:` system messages is parsed**, but messages
  invoked by extensions are often surfaced via `wfMessage(...)->text()`
  (raw, no parser). Test the live page after every edit. Lockdown's deny
  pages — `MediaWiki:Loginreqpagetext`, `MediaWiki:Badaccess-groups`,
  `MediaWiki:Badaccess-group0` — go through the parser, so `{{Ambox}}`
  works there.
- **Namespace-prefix collisions.** Once `NS_IT=3000` is registered, any
  page title starting with `IT:` resolves to NS_IT. Pages saved into
  NS_MAIN with a literal `IT:` prefix become unreachable by URL. The
  fix is a direct `UPDATE page SET page_namespace=3000, page_title=…`
  via a Maintenance script — `MovePage::moveIfAllowed` no-ops because
  source and target prefixed-text are identical.
- **Categories**: every published page gets at least one
  `[[Category:…]]` tag. The canonical sixteen are listed on
  `Category:Categories` after the 2026-05-02 consolidation.

---

## CSS conventions

`MediaWiki:Common.css` carries the site's reusable widget styling. The
sections currently in use:

| Class | Use |
|-------|-----|
| `cttb-note` | `<div class="cttb-note">…</div>` — Note callout |
| `cttb-warning` | yellow Warning callout |
| `cttb-tip` | green Tip callout |
| `cttb-alert` | red firm-notice block (border + shadow) |
| `cttb-code` / `cttb-pre` | inline / block code with subtle bg |
| `cttb-restricted-link` | applied automatically by the link hook to
  every link to a Lockdown-protected namespace; viewer-aware via
  `body.cttb-user-in-<group>` rules. Don't hand-apply. |

The Mbox family (`ambox`, `ombox`, `imbox`, `cmbox`, `tmbox`, `fmbox`)
also has unscoped fallback rules in Common.css so the border / cell
layout renders on system messages outside `.mw-parser-output` (the
TemplateStyles version is parser-output-scoped and won't apply on
deny pages).

---

## Authoring a Lockdown-protected page

1. Save the draft with the namespace prefix in the title:
   `IT:Foo Bar.txt` → wiki page `IT:Foo Bar` (NS_IT=3000).
2. Push with `utils/wiki edit "IT:Foo Bar" .claude/wiki-pages/IT_Foo_Bar.txt "summary"`.
3. The `HtmlPageLinkRendererBegin` hook will automatically prefix any
   link to this page with 🔒 for non-`it`-group viewers, and the body
   class hook will reveal the link normally for IT members.
4. Anonymous visitors hit `MediaWiki:Loginreqpagetext` (Mbox-styled);
   logged-in non-IT users hit `MediaWiki:Badaccess-groups`.

---

## Where to look

| What | Where |
|------|-------|
| Style rulebook | `WIKISTYLE.md` (in this skill folder) |
| Live wiki | `http://wiki.cttb` |
| Container | `srv-vm` LXC `wiki-2404` (10.11.1.34) — shell via `/cttb-host` |
| Ansible role | `roles/mediawiki/` |
| LocalSettings template | `roles/mediawiki/templates/LocalSettings.php.j2` |
| Per-host vars (namespaces, lockdown rules) | `host_vars/wiki-2404/main.yml` |
| Wiki tooling | `utils/wiki` (unified CLI: `probe`/`get`/`edit`/`purge`/`history`/`upload`/`sitenotice`/`delete`/`maint`/`audit-drafts`) |
| Container shell / vault | units `/cttb-host`, `/cttb-vault` |
| Local draft directory | `.claude/wiki-pages/` |
| API endpoint | `http://wiki.cttb/w/api.php` (the `wiki` CLI handles auth per command) |
| Bot identity | `<redacted>` (creds in macOS Keychain — `WIKI_CTTB_BOT_USER`, `WIKI_CTTB_BOT_PASSWD`) |
| Special pages of interest | `Special:RecentChanges`, `Special:AllPages`, `Special:UserRights`, `Special:Version` |

---

## Pre-publish checklist

Run through this before every `utils/wiki edit` push. Most
items come from WIKISTYLE; the CTTB-specific ones are added on top.

- [ ] **Lead** — first sentence is a bolded title + one-clause
  definition, no "this article describes" framing, no bullets.
- [ ] **Prose first** — body explains as connected paragraphs;
  bullets only where the items are genuinely parallel.
- [ ] **At least one figure** for any architecture / pipeline /
  topology page, with a caption that stands on its own.
- [ ] **References** — `<ref>` tags for every external claim, and
  `== References ==\n<references />` near the bottom.
- [ ] **Headings in sentence case** (not title case).
- [ ] **No `= Title =` h1** at the top — MediaWiki renders the page
  title; including one duplicates it.
- [ ] **`<nowiki>` around any literal `{{…}}` or `[[…]]`** in body
  text, including inside `<code>` (the parser still expands inside
  `<code>`).
- [ ] **Categories** — at least one `[[Category:…]]` at the very
  bottom; check `Category:Categories` for the canonical sixteen.
- [ ] **Templates on first use** — does this page need a
  `{{IT Infrastructure}}` header, an `{{Ambox}}` notice, or a
  category-shape template? Reuse before inventing.
- [ ] **TOC sanity check** — count the `==` headers; if it's
  more than ~6 and any clusters share an audience or sub-task
  family, regroup under parent headers (see "Section hierarchy"
  above). A flat scroll of fifteen peer sections is a smell.
- [ ] **Lockdown** — if the page belongs in a restricted namespace
  (`IT:`, `DRBU:`, `DVGS:`, `DVBS:`, `CTTB:`), is the title prefix
  correct so it lands in the right namespace?
- [ ] **Purge** — after pushing, run `utils/wiki purge
  "Page Title"` (add `--force` for `Template:` edits) so the next
  viewer sees the new render rather than the cached old one.
