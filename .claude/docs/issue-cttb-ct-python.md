## Summary

`.claude/sysadmin/cttb-ct.sh` is the last bash tool in the sysadmin toolkit; every other CLI (`wiki`, `ldap`, `vault-pass`, and now `load-cttb-key`) is Python on the shared `cttb_api` layer. Port it to Python so the whole toolkit is cross-platform (macOS / Windows-WSL / Linux) and shares one credential + SSH abstraction.

## Motivation

- **Cross-platform.** The bash script assumes a POSIX shell, `ssh`/`scp` in `$PATH`, and bash-specific `case`/`ssh_chain()` host tables. A Python port using `subprocess` + the existing `cttb_api.ssh_exec()` runs the same on Windows.
- **Single source of host truth.** The host/container → SSH-chain tables currently live only in the bash `ssh_chain()` case. A Python module can share them with any other tool that needs to resolve a host.
- **Consistency.** `cttb_api` already exposes `ssh_exec(...)` and a `CttbContext.ssh()`; the port should build on those rather than re-implementing ProxyJump handling.

## Scope

- [ ] `cttb-ct` (Python) with the current subcommands: `list`, `shell <alias>`, `exec <alias> <cmd...>`, `push <alias> <local> <remote>`, `pull <alias> <remote> <local>`.
- [ ] Host/container alias table + SSH chain (ProxyJump for `*.cttb`) moved into a Python module (e.g. `cttb_hosts.py`) importable by other tools.
- [ ] `shell` gives an interactive session (allocate a TTY — `os.execvp` into `ssh` is acceptable for the interactive path).
- [ ] Behavioral parity verified against the current script for at least `list`, `exec`, `push`, `pull` on one reachable host.
- [ ] Update references in `CLAUDE.md`, `PROJECT.md`, and the skills that invoke it (`/cttb-host`, `.claude/skills/*`) from `cttb-ct.sh` to `cttb-ct`.
- [ ] Keep a thin `cttb-ct.sh` shim that execs the Python entry, or update all callers in the same PR.

## Where to look first

- `.claude/sysadmin/cttb-ct.sh` — the `ssh_chain()` case is the core to port.
- `.claude/sysadmin/cttb_api.py` — `ssh_exec()` and `CttbContext.ssh()` to build on.
- `~/.ssh/config` — the ProxyJump for `*.cttb` the script relies on.

## Context

Raised 2026-07-30: the operator asked that all sysadmin tools be Python for cross-platform promotion, while adding the Python `load-cttb-key`. `cttb-ct.sh` is the one remaining bash holdout. Not urgent — the tool works today on macOS/Linux — but it is the last blocker to a uniformly Python, Windows-capable toolkit.
