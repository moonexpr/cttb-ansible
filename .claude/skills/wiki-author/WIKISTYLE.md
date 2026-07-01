# WIKISTYLE.md — Wikipedia Manual of Style for CTTB-style technical wikis

Synthesized from [WP:MOS](https://en.wikipedia.org/wiki/Wikipedia:Manual_of_Style), [WP:MOS/Computer science](https://en.wikipedia.org/wiki/Wikipedia:Manual_of_Style/Computer_science), [WP:MOS/Lead section](https://en.wikipedia.org/wiki/Wikipedia:Manual_of_Style/Lead_section), [WP:MOS/Layout](https://en.wikipedia.org/wiki/Wikipedia:Manual_of_Style/Layout), [WP:MOS/Linking](https://en.wikipedia.org/wiki/Wikipedia:Manual_of_Style/Linking).

> Read this whenever drafting or revising a wiki article in the spirit of Wikipedia. The /compose skill governs voice and warmth; WIKISTYLE governs *structural conventions* — what makes the page recognizably encyclopedic. Apply both. The two do not conflict: encyclopedic voice can still be warm in framing and personal in attribution.

---

## 1. Lead section

The lead is the first thing every reader sees. It exists to tell the reader, in under a minute, what the topic is, why it matters, and what the rest of the article covers.

- **DO NOT include a wikitext `= Page Title =` h1 at the top of the page.** MediaWiki automatically renders the page title (from the URL/page name) as a styled `<h1>`. Adding `= Foo =` as the first line creates a duplicate visible heading — the `<h1>` from MediaWiki appears, and immediately below it your second `<h1>` appears as another large heading. The lead section starts with the first paragraph, with no heading above it. The first body section heading should be `==` (h2). This bites every author at least once. The mechanical fix is to delete the first `= Title =` line from any draft before publishing.
- **First sentence: bolded title + one-clause definition.** When the article title appears verbatim in the first sentence, set it in bold. Define the topic — do not announce that the article will discuss it.
  - Correct: `'''CUPS''' is the printing system used on every CTTB lab machine.`
  - Wrong: "This article describes CUPS." (MOS:REFERS — the article is about the subject, not about a term for the subject.)
- **No second person.** Avoid "you" / "your" in the lead (and throughout). Use the noun, the third person, or passive voice.
- **No bullet points in the lead.** Lead is running prose only. Bullets appear in the body.
- **Length.** Featured-article leads run 250–400 words; few well-written leads are shorter than 100. For a 5–15 KB technical page, one good paragraph (3–6 sentences) typically suffices.
- **Don't bury the link.** Avoid placing the article's primary link inside the bolded title; let the bold stand alone (MOS:BOLDLINKAVOID).
- **Date qualifiers** in the first sentence are fine when they help the reader confirm they have the right page (E.g., "as of 2026 …").

---

## 2. Headings

- **Sentence case, not title case.** "Adding a new printer," not "Adding A New Printer." This is the single biggest change most external authors need to make. Capitalize only the first word and proper nouns.
- **No first or second person, no questions, no images** in headings.
- **Avoid restating the article title** in section headings. On a page titled "NFS," prefer the section heading "Subnet ACLs" over "NFS subnet ACLs."
- **Hierarchy:** `==` for top-level body sections (h2), `===` for subsections (h3). Reserve `=` (h1) for the page title only — most wikis render it from the title automatically.
- **One blank line** between paragraphs and between sections. No more, no less.

---

## 3. Voice and tone

- **Encyclopedic, not instructional.** Wikipedia is not a how-to manual. Where a procedure must be documented (and on a sysadmin wiki, it often must), present it as factual description rather than as commands directed at the reader. "The administrator runs <code>passwd</code>" rather than "You should run <code>passwd</code>."
- **No first-person plurals** ("we," "our," "us") for editorial voice. Acceptable for historical narrative ("only fragments have come down to us") and for the author's *we* in scientific writing, but watch the line.
- **No "note that," "remember that," "it should be noted."** These address the reader directly. Just state the fact.
- **No peacock or weasel words** ("the most powerful," "supposedly," "so-called") unless attributed to a named source.
- **No "click here," "see below" as bait.** State what is at the link or in the section.

---

## 4. Code formatting (MoS/CS)

- **Inline code: `<code>...</code>`.** Use for filenames, command names, paths, identifiers, configuration keys, short snippets. Wraps cleanly in prose.
- **Block code: `<syntaxhighlight lang="x">...</syntaxhighlight>` or `<pre>...</pre>`.** Prefer `syntaxhighlight` when the language is well-known (`bash`, `python`, `yaml`, `ini`, `apache`, `nginx`); fall back to `<pre>` for ad-hoc transcripts and command-line sessions. Indenting with a leading space also produces a `<pre>` block but is less readable in source.
- **Variables in syntax: `<var>...</var>` or italic.** When showing a command template, mark placeholders: `ssh administrator@<var>hostname</var>.cttb`.
- **Avoid esoteric languages in shared examples.** Where possible use Python or shell — languages that read clearly to non-specialists. (For our wiki, Bash and YAML dominate; Python next.)
- **License-compatible code only.** Snippets must be compatible with CC-BY-SA. Don't paste GPL code wholesale.

---

## 5. Capitalization, abbreviations, and naming

- **Don't capitalize a word in prose just because the abbreviation is capitalized.** "An early local area network (LAN) was deployed" — not "An early Local Area Network (LAN)."
- **Expand on first use:** "the City of Ten Thousand Buddhas (CTTB)." Common, well-known abbreviations (DNS, HTTP, USB, SSH, LDAP) can stand without expansion.
- **Acronym plurals** take a plain `-s`: "two BIOSes," "three CD-ROMs." Never "BIOS's."
- **Periods inside acronyms:** Use **GDP**, not **G.D.P.**; use **US**, not **U.S.** (Wikipedia commonality default).
- **Software, language, and protocol names** follow upstream casing: nginx (lowercase), Apache (capitalized), MediaWiki, OpenLDAP, systemd (lowercase), PostgreSQL, JavaScript, MariaDB.

---

## 6. Italics and emphasis

- **Italics for emphasis** — sparingly. Overuse "diminishes its effect."
- **Italics for non-English words** that are not in everyday English use (`<lang>` template ideal). Proper nouns are not italicized.
- **Italics for *use–mention*:** The word *foo* refers to a placeholder identifier.
- **Bold for the article title's first appearance** in the lead, and for alternative names. Never for emphasis.

---

## 7. Lists vs prose

- **Default to prose.** Use lists only when prose would be harder to read.
- **Don't use bullets in the lead.** Lead is always paragraphs.
- **Use numbered lists only when order matters** or when items will be referenced by number.
- **No blank lines between bullet items** (it breaks the list visually and at the markup level).
- Reference, further-reading, and external-links sections are typically bulleted by convention.
- **List items begin with a capital letter.** End with a period only if the item is a complete sentence.

---

## 8. Tables

- **Use a table only when comparing data across rows and columns.** A table is the right shape when you would otherwise write "for X, the value is A; for Y, the value is B; for Z, the value is C." Don't use tables to lay out two paragraphs side-by-side.
- **Table captions and column headers** follow sentence case (same rule as section headings).
- **Use `class="wikitable"`** for the campus default styling.
- **Avoid collapsed-by-default content** — readers can't search what they can't see. Don't hide article content inside collapse templates.

---

## 9. Linking

- **Link the first significant occurrence** of a relevant term. Do not link the same term repeatedly within the same article (acceptable to link again in the See Also or in a distant section if the link aids navigation).
- **Don't link everyday words** (DNS, server, password, file, software, computer). Most readers know them; the link is friction.
- **Link technical terms** the reader may not know (E.g., on an LDAP page, link `posixAccount`, `STARTTLS`, `slapcat`).
- **Don't link the page back to itself** (MOS:CIRCULAR).
- **External links** belong at the bottom in their own section, or as inline references — not as the body's primary navigation.

---

## 10. See also

- **Plain bulleted list of internal links.** No annotations, or only minimal ones.
- **One blank line** before the section.
- **Each entry begins with a capital letter.**
- **Sort logically, chronologically, or alphabetically** — be consistent within a page.
- **Don't repeat links** that already appear in the body. See also is for related topics not yet linked, not a duplicate index.
- The section is **optional**; many strong articles omit it.

---

## 11. References and footnotes

- **`<ref>...</ref>`** for inline references; **`<references />`** at the bottom under `== References ==`.
- **Cite at the end of the sentence** the reference supports, after punctuation.
- **Reuse references** with `<ref name="key">...</ref>` first, then `<ref name="key" />` thereafter.
- **Glossary-style footnotes** (defining a term with `<ref>'''Term:''' definition</ref>`) are acceptable on a technical wiki even though Wikipedia itself prefers separate Notes vs References sections. Keep them for terms a reader may not know but that can be defined in one line.

---

## 12. Section ordering (Layout)

For a typical article, sections appear in this order from top to bottom:

1. Lead (no heading)
2. Body sections (`==` headings)
3. **See also** (optional)
4. **Notes** (optional, separate from refs)
5. **References** (`<references />`)
6. **Further reading** (optional)
7. **External links** (optional)
8. Categories (`[[Category:...]]`)

Categories at the very bottom, no blank line between them.

---

## 13. Specific anti-patterns to avoid

- "This page is about …" / "This article describes …" — define the topic, don't describe the page.
- "Note that …" / "Remember to …" / "You'll want to …" — drop the address-to-reader.
- "Click here" / "See below" / "Just" — bait or hedge.
- Title-case headings.
- Bullets in the lead.
- A `==See Also==` heading that is just a list of links to pages already linked above.
- An External Links section composed entirely of inline reference URLs (move them to `<ref>` tags).

---

## 14. Where /compose voice and WIKISTYLE structure overlap

| Concern | /compose says | WIKISTYLE says | Resolution |
|---|---|---|---|
| Warmth | "Open with acknowledgment" | "Define the topic in the first sentence" | Define first; warmth lives in the body, especially in attribution ("Spike originally suggested the reprepro setup …") |
| Em-dashes | "Closed em-dashes—like this" | (silent) | Keep closed em-dashes |
| Soft hedges ("I wanted to") | Welcome | Avoid "I" / "we" in editorial voice | Use sparingly and only in clearly attributed historical narrative, not as the article's own voice |
| Sentence rhythm | "Vary deliberately" | (silent) | Keep variety, but don't sacrifice precision |
| Closing sign-off | "Warm regards … John Ott Chandara" | (silent) | Wiki articles are not signed; signature applies to correspondence only |

---

## Quick checklist before publishing

- [ ] **No `= Title =` h1 at the top of the wikitext** (MediaWiki renders the page title automatically — including one yields a duplicate visible h1)?
- [ ] First sentence: bold article title + concise definition?
- [ ] Headings in sentence case, no title-case slips?
- [ ] Every embedded image uses `[[File:xxx|thumb|right|400px|caption]]` (or similar) so it renders inside a figure box with a caption — never bare `[[File:xxx]]` which gives a full-bleed unboxed image?
- [ ] No "you / your" addressed at the reader?
- [ ] Inline code wrapped in `<code>...</code>`?
- [ ] Block code in `<syntaxhighlight>` or `<pre>`?
- [ ] Acronyms expanded on first use?
- [ ] No bullets in the lead?
- [ ] See also: plain bulleted list, no annotation, capitalized entries?
- [ ] References section with `<references />` if any `<ref>` tags exist?
- [ ] Categories at the bottom?
- [ ] No "this page describes" or "click here" or "note that"?

---

## Source pages (for follow-up)

- [WP:MOS](https://en.wikipedia.org/wiki/Wikipedia:Manual_of_Style) — main MoS
- [WP:MOS/Computer science](https://en.wikipedia.org/wiki/Wikipedia:Manual_of_Style/Computer_science) — code samples, pseudocode, tech naming
- [WP:MOS/Lead section](https://en.wikipedia.org/wiki/Wikipedia:Manual_of_Style/Lead_section) — first sentence rules, lead length
- [WP:MOS/Layout](https://en.wikipedia.org/wiki/Wikipedia:Manual_of_Style/Layout) — section ordering, See also, paragraphs
- [WP:MOS/Linking](https://en.wikipedia.org/wiki/Wikipedia:Manual_of_Style/Linking) — overlinking, what to link
- [WP:MOS/Capital letters](https://en.wikipedia.org/wiki/Wikipedia:Manual_of_Style/Capital_letters) — capitalization
- [WP:MOS/Text formatting](https://en.wikipedia.org/wiki/Wikipedia:Manual_of_Style/Text_formatting) — italics, bold, code
