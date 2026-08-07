## Repro

```bash
cd cttb-ansible
ansible cttb_hosts -i inventory/hosts --list-hosts | head -1   # hosts (105):
ansible all -i inventory/hosts --list-hosts | head -3          # hosts (312): '*' 'test-slim2' ...
utils/pb distribute-ssh-keys --check                           # never touches srv-*, lxc-*, etc.
```

## Expected

`plays/distribute-ssh-keys.yml` ("Distribute sysadmin SSH public keys to
administrator@ **fleet-wide**", per its header and
`docs/sysadmin-onboarding.md` §8) reaches every administrator-model host,
including the core infrastructure. `ansible all` contains no host literally
named `*`.

## Actual

- `cttb_hosts:children` = `dvgs`, `dvbs`, `drbu` only (105 hosts) — the
  school workstation fleets. `srv-gw`, `srv-vm`, `srv-nas`, `srv-bk-*`,
  the `lxc-*` containers, and ~200 other entries in `inventory/hosts`
  lines 1–380 are in **no group at all**, so the distribution play never
  reaches them. A key enrolled per onboarding §8 does not open the servers.
- `inventory/hosts:12` reads `* ansible_user=administrator`; INI inventory
  parses this as a **host named `*`**, which then appears in `all` runs and
  fails with `ssh: Could not resolve hostname *: Bad value for ai_flags`.

## Repo locations

- `/inventory/hosts` (line 12 stray `*` host; lines 1–380 ungrouped entries;
  line 618 `[cttb_hosts:children]`)
- `/plays/distribute-ssh-keys.yml` (targets `cttb_hosts`)
- `/plays/distribute-ssh-keys-infra.yml` (workaround, added 2026-07-29)
- `/docs/sysadmin-onboarding.md` §8 (claims fleet-wide coverage)

## Acceptance criteria

- [ ] Ungrouped infra entries are collected into a named group (e.g.
      `[infra]` / `[servers]` / `[lxc]` as appropriate).
- [ ] Either `cttb_hosts:children` includes that group, or the
      distribution play's `hosts:` pattern covers it explicitly; the
      stopgap `distribute-ssh-keys-infra.yml` is then folded in or removed.
- [ ] `inventory/hosts` line 12 is converted to a proper group var
      (`[all:vars]` or equivalent) and `ansible all --list-hosts` contains
      no host named `*`.
- [ ] `utils/pb distribute-ssh-keys --check` shows srv-vm/srv-gw/srv-nas
      in the recap.

## Workaround

```bash
utils/pb distribute-ssh-keys-infra --check   # preview
utils/pb distribute-ssh-keys-infra           # infra complement (added 2026-07-29)
```

## Where to look first

`inventory/hosts` — the ungrouped block (lines 1–380) and the `*` line.
Related but distinct: #98 (three different inventory *paths*).

## Context

Discovered 2026-07-29 while distributing jc's enrolled key fleet-wide from
CTTB_TRUSTED_HOST. The main play reported success yet the Mac still could
not reach `administrator@srv-vm`, because the servers were never in the
play's target set. Also bitten in the same session:
`host_vars/srv-gw` had a literal tab (fixed in 4d773348) that aborted any
`all`-pattern play at var-load time.
