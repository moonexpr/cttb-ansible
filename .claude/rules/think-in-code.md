# Rule: Think in Code (project-vendored for cttb-ansible)

> Vendored from the global `~/.claude/rules/think-in-code.md` so sysadmins who
> clone this repo get the same enforcement without a global install. The
> authoritative global version lives at `~/.claude/rules/think-in-code.md`;
> this copy is the project-scoped fallback.

**Default: program the analysis, do not compute it.** When the question is
"count X", "find all Y", or "aggregate Z", write (or call) a script that
prints only the answer. Do not stream raw data into the context window and
think about it line by line.

This rule has the same status as `rules/script-persistence.md` (global) — in
force unless an escape hatch is invoked deliberately. Per-call enforcement
lives in `.claude/hooks/pre-tool-think-in-code.py` (deny), wired through
`.claude/settings.json`'s `PreToolUse` hook so it fires in every session that
loads this project — no global install required.

---

## Forbidden patterns

The gate watches for four failure modes:

1. **Multi-Read for aggregation.** Reading 10+ files to count or summarize
   across them. Replacement: write a script that loops the files and prints
   the aggregate; run it via
   `mcp__plugin_context-mode_context-mode__ctx_execute_file`.

2. **Unbounded grep / find / rg.** `grep -r`, `find . -type f`, bare
   `rg pattern` without a count/list flag or a path-bound + head-pipe.
   Replacement: `mcp__plugin_context-mode_context-mode__ctx_batch_execute`
   with the same command — output is auto-indexed and only a printed summary
   returns to context. Follow up with `ctx_search` to query the indexed
   corpus.

3. **Bash dumping to context.** Any Bash call whose output exceeds
   `THINK_IN_CODE_OUTPUT_THRESHOLD` bytes (default 2048). `cat` of a large
   file, `ls -la` of a huge tree, `jq` over a megabyte of JSON. Replacement:
   `mcp__plugin_context-mode_context-mode__ctx_execute(language: "shell",
   code: "...")` — only the printed summary enters context.

4. **Raw curl/wget against `wiki.cttb`.** Hand-rolled HTTP to the wiki API
   bypasses the sysadmin `wiki` CLI (auth, drafts workflow, purge batching)
   and is denied everywhere — in Bash **and** inside the `ctx_*` sandbox
   tools. Replacement: `utils/wiki`
   (`probe`/`get`/`edit`/`purge`/`history`/`upload`/`delete`/`maint`/
   `audit-drafts`). If a capability is missing, extend the CLI
   (`wiki_lib.py`) per `script-persistence.md` — the next agent inherits
   the subcommand instead of re-improvising HTTP.

---

## Approved replacements

| Need | Replacement |
|------|-------------|
| Recursive search / grep | `ctx_batch_execute` (commands run, output indexed) |
| Query an already-indexed corpus | `ctx_search` (FTS5, low-token result) |
| Analyze a file's contents | `ctx_execute_file(path, language, code)` |
| Multi-step shell pipeline | `ctx_batch_execute(commands)` |
| Any wiki.cttb API operation | `utils/wiki` CLI (extend it if a subcommand is missing) |
| Reusable analysis primitive | a skill's `scripts/` folder (per `script-persistence.md`) |

---

## Tuning knobs (environment variables)

| Variable | Default | Meaning |
|----------|---------|---------|
| `THINK_IN_CODE_DISABLE` | unset | If exported, the gate passes everything through. Per-command opt-out: prefix the command with `THINK_IN_CODE_DISABLE=1` (e.g. `THINK_IN_CODE_DISABLE=1 grep -r foo .`). |
| `THINK_IN_CODE_OUTPUT_THRESHOLD` | 2048 | Bytes of tool output above which a PostToolUse reminder would fire (the project install ships the PreToolUse deny hook; the PostToolUse warn hook is optional/global). |
| `THINK_IN_CODE_DENY_DISABLE` | unset | If exported, PreToolUse denies become non-blocking (the warn path is not vendored at the project scope). For sessions where you genuinely need to fly raw. |
| `THINK_IN_CODE_DEBUG` | unset | Log gate decisions to `/tmp/think-in-code.log`. |

---

## What "sample reads" means

When the gate redirects a Grep or Bash-grep, the call routes through
`ctx_batch_execute`, which runs the underlying command, **indexes the full
output into the context-mode database**, and returns only a printed summary
(first N matches, total count, index pointer). The full result remains
queryable via `ctx_search` without ever entering the chat context. The
principle: **persistent index, ephemeral context.**

The token cost of one `ctx_search` query is O(matches you actually want),
not O(everything that matched). That asymmetry is the whole game.

---

## Why this rule exists

A 50-file Read consumes ~100K tokens to answer a question whose answer is
one integer. A scripted equivalent prints that integer. The LLM is a code
generator first, a data processor only when no script will do.

See also: `rules/script-persistence.md` (global — where reusable scripts live).