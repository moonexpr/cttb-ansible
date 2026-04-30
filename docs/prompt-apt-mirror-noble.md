# Task: Add Ubuntu 24.04 (Noble) to apt.cttb debmirror

## Context

We're upgrading ~20 lab machines from Ubuntu 20.04 to 24.04. The local apt mirror (`apt.cttb`) only has focal and xenial — no noble packages. Every playbook run currently pulls 1GB+ over WAN via `deb_mirror=http://archive.ubuntu.com`. This is a blocker for mass rollout.

See `UPDATE_JOURNAL.md` in this repo for full project context, especially:
- "Backlog: Pre-Mass-Upgrade Checklist" section (search for "apt.cttb mirror missing Noble")
- "2026-04-23 — Core Services Audit" section for infrastructure map

## Infrastructure

- **debmirror container**: `debmirror` at 10.11.1.22, runs on srv-nas (10.11.1.5), Ubuntu 16.04
- **apt.cttb web server**: `apt` DNS resolves to the debmirror container, serves via apache2
- **Current mirror contents**: focal, xenial (check `/etc/debmirror.conf` or equivalent on the container)
- **PXE/asset server**: `pxe.cttb` at 10.11.1.23 (separate container, also on srv-nas)

## Access

- SSH: `ssh administrator@srv-nas.cttb` (ed25519 key deployed), then `lxc exec debmirror -- bash`
- Or direct if DNS resolves: `ssh administrator@debmirror.cttb` (may not have key — check)
- See `reference_pxe_server.md` in `.claude/projects/` memory for SSH details

## Goal

1. SSH into the debmirror container and find the current mirror config (likely `/etc/debmirror.conf`, a cron script, or a wrapper in `/usr/local/bin/`)
2. Determine disk space available and space needed for noble (amd64, main+restricted+universe+multiverse)
3. Add noble to the mirror config alongside existing focal/xenial
4. Run an initial sync (or schedule one — it'll take hours)
5. Verify `http://apt.cttb/mirrors/ubuntu/dists/noble/` serves correctly
6. Document what you changed in `UPDATE_JOURNAL.md`

## Constraints

- The debmirror host is Ubuntu 16.04 — its `debmirror` package may be too old to sync noble. If so, consider `apt-mirror` or `rsync` from `archive.ubuntu.com` as alternatives.
- Don't break existing focal/xenial mirrors — other machines still use them.
- The container may have limited disk. Check `df -h` before syncing. A full noble mirror (main+restricted+universe+multiverse, amd64) is ~150GB. If space is tight, consider mirroring only main+restricted+universe.

## Verification

```bash
# From any lab machine or your Mac
curl -sI http://apt.cttb/mirrors/ubuntu/dists/noble/Release | head -5
# Should return HTTP 200

# Then test the playbook without the deb_mirror override:
source utils/setup-env
ansible dvgs-lab3.cttb -m apt -a "update_cache=yes" -e "ansible_ssh_pass=a ansible_become_pass=a ansible_python_interpreter=/usr/bin/python3"
```
