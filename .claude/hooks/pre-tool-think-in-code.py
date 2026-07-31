#!/usr/bin/env python3
"""PreToolUse hook (project-scoped): redirect context-flooding tool calls to
context-mode.

Vendored from ~/.claude/hooks/pre-tool-think-in-code.py for cttb-ansible so every
sysadmin who clones the repo gets the same enforcement without a global install.
Watches Bash and the context-mode sandbox tools (ctx_execute /
ctx_execute_file / ctx_batch_execute). For Bash, examines the command and
denies recursive/unbounded patterns that typically produce >2KB of output,
allowing bounded variants (--count, -l, -c, piped through head/wc, etc.)
through, and denies raw curl/wget against wiki.cttb (use the sysadmin `wiki`
CLI). For the ctx tools, only the wiki-curl check applies — grep/find/cat are
exactly what those tools are for, but a curl to the wiki API is a CLI bypass
no matter which sandbox runs it.

Escape hatches:
  - Per-command: prefix with `THINK_IN_CODE_DISABLE=1` (e.g.
    `THINK_IN_CODE_DISABLE=1 grep -r foo .`)
  - Session-wide: `export THINK_IN_CODE_DISABLE=1`
  - Warn-only mode: `export THINK_IN_CODE_DENY_DISABLE=1` (denies become
    PostToolUse warnings)
"""
# `from __future__ import annotations` makes annotations lazy strings, so the
# `tuple[bool, str]` return hint below works on Python 3.7/3.8 too (subscripted
# builtins as runtime annotations otherwise need 3.9+).
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path


def is_disabled(command: str) -> bool:
    """Per-command or session-wide opt-out."""
    if os.environ.get('THINK_IN_CODE_DISABLE'):
        return True
    if 'THINK_IN_CODE_DISABLE=1' in command:
        return True
    return False


def deny_disabled() -> bool:
    """Warn-only mode."""
    return bool(os.environ.get('THINK_IN_CODE_DENY_DISABLE'))


def debug_log(msg: str) -> None:
    if not os.environ.get('THINK_IN_CODE_DEBUG'):
        return
    try:
        with open('/tmp/think-in-code.log', 'a') as f:
            f.write(msg + '\n')
    except Exception:
        pass


# ── Per-tool matchers ────────────────────────────────────────────────────────
# Each matcher operates on a single command segment (split on |, ;, &, &&).
# Returns (deny, pattern_name) or (False, '').

def _has_grep_recursive(seg: str) -> bool:
    # Matches -r, -R, -rn, -Rni, etc. — any short-flag cluster containing r/R.
    return bool(re.search(r'\bgrep\b[^|;&]*\s-[a-zA-Z]*[rR]', seg))


def _has_grep_count_or_list(seg: str) -> bool:
    return bool(re.search(r'\bgrep\b[^|;&]*\s-[a-zA-Z]*[lc]', seg))


def _check_grep(seg: str):
    if not re.search(r'\bgrep\b', seg):
        return None
    if _has_grep_recursive(seg) and not _has_grep_count_or_list(seg):
        return 'recursive grep without -l/-c'
    return None


def _check_rg(seg: str):
    if not re.search(r'(?:^|\s)rg\b', seg):
        return None
    bounded = re.search(
        r'\brg\b[^|;&]*(?:--count|--files-with-matches|--files|\s-[a-zA-Z]*[cl]\b)',
        seg,
    )
    if bounded:
        return None
    return 'unbounded rg'


def _check_find(seg: str):
    if not re.search(r'\bfind\b', seg):
        return None
    # Bounded by depth, by name filter, or by -delete/-exec sink.
    if re.search(r'\bfind\b[^|;&]*-maxdepth\s+\d+', seg):
        return None
    if re.search(r'\bfind\b[^|;&]*-name\s+\S+', seg):
        return None
    if re.search(r'\bfind\b[^|;&]*-iname\s+\S+', seg):
        return None
    if re.search(r'\bfind\b[^|;&]*-(?:delete|exec)\b', seg):
        return None
    return 'unbounded find'


def _check_cat(seg: str):
    # Match `cat <file>` segments; allow heredoc, redirects, command substitution.
    if not re.search(r'\bcat\b', seg):
        return None
    if '<<' in seg:  # heredoc
        return None
    if re.search(r'\bcat\b\s+[^\s|<>;&]+', seg):
        # Bare cat of a file — segment-local check (this segment has no pipe/redirect
        # because we already split on |;&). Allow output redirection within segment.
        if '>' in seg:
            return None
        return 'cat without pipe'
    return None


def _check_wiki_curl(seg: str):
    # Raw HTTP against the campus wiki bypasses the sysadmin `wiki` CLI
    # (auth, drafts workflow, purge batching). Denied regardless of downstream
    # sinks — piping the API response through head is still a raw API call.
    # curl/wget must be the command word (optionally after env prefixes /
    # sudo / time), not merely a word in an argument — otherwise a commit
    # message or echo that *mentions* curling the wiki trips the gate.
    invoked = re.match(
        r'^(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:sudo\s+|time\s+)*(?:curl|wget)\b',
        seg.strip(),
    )
    if not invoked:
        return None
    if re.search(r'wiki\.cttb|10\.11\.1\.34', seg):
        return 'raw curl/wget against wiki.cttb'
    return None


# The downstream-pipe exceptions: if a deny-worthy command is followed by
# head/wc/tail/xargs in the *next* segment, allow the whole pipeline.
PIPE_SINK_RE = re.compile(r'\b(?:head|wc|tail|xargs)\b')


def check_bash(command: str) -> tuple[bool, str]:
    """Return (should_deny, pattern_name) for a Bash command."""
    if is_disabled(command):
        return False, ''

    # Strip leading env-var prefixes (FOO=bar BAZ=qux <cmd>).
    body = re.sub(r'^(?:[A-Za-z_][A-Za-z0-9_]*=\S+\s+)+', '', command.strip())

    # Split on pipe / sequencer. We deliberately do not parse subshells;
    # the heuristic is conservative.
    segments = re.split(r'\|+|;|&&|\|\|', body)
    segments = [s.strip() for s in segments if s.strip()]
    if not segments:
        return False, ''

    # Wiki-CLI bypass check first — no downstream-sink exemption applies.
    for seg in segments:
        name = _check_wiki_curl(seg)
        if name:
            return True, name

    matchers = (_check_grep, _check_rg, _check_find, _check_cat)

    for i, seg in enumerate(segments):
        for matcher in matchers:
            name = matcher(seg)
            if not name:
                continue
            # Downstream sink (head/wc/tail/xargs) in any later segment → allow.
            downstream = ' '.join(segments[i + 1:])
            if PIPE_SINK_RE.search(downstream):
                continue
            return True, name

    return False, ''


def check_ctx(tool_input: dict) -> tuple[bool, str]:
    """Wiki-CLI bypass check for context-mode sandbox tools. Only the wiki
    matcher applies here — grep/find/cat are exactly what ctx tools are FOR."""
    chunks: list[str] = []
    if isinstance(tool_input.get('code'), str):
        chunks.append(tool_input['code'])
    for c in tool_input.get('commands', []) or []:
        if isinstance(c, dict) and isinstance(c.get('command'), str):
            chunks.append(c['command'])
    for chunk in chunks:
        if is_disabled(chunk):
            continue
        for seg in re.split(r'\|+|;|&&|\|\||\n', chunk):
            name = _check_wiki_curl(seg)
            if name:
                return True, name
    return False, ''


REDIRECT_MSG_BASH = """Blocked by think-in-code gate ({pattern}).

This command typically produces output that floods the context window. Route
it through context-mode instead — it runs the same command, indexes the
output into a searchable database, and returns only a printed summary:

  mcp__plugin_context-mode_context-mode__ctx_batch_execute(
    commands=[{{"label": "<descriptive-label>", "command": "<your shell command>"}}]
  )

Follow up with ctx_search(queries=[...]) to retrieve specific matches.

For ad-hoc analysis, use ctx_execute(language: "shell", code: "...").

Escape hatches (use sparingly, with a stated reason):
  - Per-command:   THINK_IN_CODE_DISABLE=1 <your command>
  - Warn-only:     export THINK_IN_CODE_DENY_DISABLE=1
  - Session-wide:  export THINK_IN_CODE_DISABLE=1

See .claude/rules/think-in-code.md (project-vendored) for the full principle.
"""


REDIRECT_MSG_WIKI = """Blocked by think-in-code gate ({pattern}).

All wiki.cttb API access goes through the sysadmin CLI, which carries auth,
the drafts workflow, and purge batching:

  utils/wiki probe|get|edit|purge|history|upload|delete|maint|audit-drafts

Common equivalents:
  page wikitext        wiki get --login "Title" -
  revision history     wiki history "Title" -n 5 --login
  cache purge          wiki purge "Title"          (API-based; add --force after Template edits)
  existence check      wiki probe --login "Title"

If the capability you need is missing, extend the CLI (utils/wiki
+ wiki_lib.py) rather than inlining HTTP — see the script-persistence rule.

Escape hatch (use sparingly, with a stated reason):
  THINK_IN_CODE_DISABLE=1 <your command>
"""


def _deny(reason: str) -> None:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)


CTX_TOOL_RE = re.compile(
    r'^mcp__.*context-mode__ctx_(?:execute|execute_file|batch_execute)$'
)


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)  # malformed input — don't break the tool flow

    tool_name = payload.get('tool_name', '')
    tool_input = payload.get('tool_input', {})

    if tool_name == 'Bash':
        cmd = tool_input.get('command', '')
        deny, pattern = check_bash(cmd)
        debug_log(f'Bash check: deny={deny} pattern={pattern!r} cmd={cmd!r}')
        if deny and not deny_disabled():
            msg = REDIRECT_MSG_WIKI if 'wiki.cttb' in pattern else REDIRECT_MSG_BASH
            _deny(msg.format(pattern=pattern))
        # If deny_disabled, fall through — PostToolUse hook will warn instead.

    elif CTX_TOOL_RE.match(tool_name):
        deny, pattern = check_ctx(tool_input)
        debug_log(f'ctx check: deny={deny} pattern={pattern!r} tool={tool_name}')
        if deny and not deny_disabled():
            _deny(REDIRECT_MSG_WIKI.format(pattern=pattern))

    sys.exit(0)


if __name__ == '__main__':
    main()