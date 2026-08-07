## Repro

Current naming of the PXE subsystem's repo objects:

```
ls roles/ | grep netinstall        # netinstall, netinstall-2404
ls plays/ | grep netinstall        # netinstall-2404.yml, deploy-netinstall-2404.yml
grep -c '^ni_' roles/netinstall-2404/defaults/main.yml   # ni_* variable prefix throughout
```

## Expected

The subsystem that provisions machines over PXE is named `pxe-*`: e.g. `roles/pxe` (legacy), `roles/pxe-2404`, `plays/pxe-2404.yml`, `plays/deploy-pxe-2404.yml`. Operators grepping for "pxe" find the roles that implement it.

## Actual

Everything is named `netinstall-*` with a `ni_` variable prefix, a historical name that no longer matches how the subsystem is referred to (host `pxe.cttb`, container `pxe24`, skills `/cttb-pxe-wait`, tags `ni_pxe*`).

## Repo locations

- `/Users/jc/GitRepos/cttb-ansible/roles/netinstall/`
- `/Users/jc/GitRepos/cttb-ansible/roles/netinstall-2404/`
- `/Users/jc/GitRepos/cttb-ansible/plays/netinstall-2404.yml`
- `/Users/jc/GitRepos/cttb-ansible/plays/deploy-netinstall-2404.yml` (also touched by #70)
- `group_vars/pxe-server.yml`, `group_vars/cttb_hosts.yml` (references)
- `.claude/skills/cttb-pxe-wait/`, docs, `PROJECT.md`, wiki references

## Acceptance criteria

- [ ] `roles/netinstall` → `roles/pxe` (or agreed name), `roles/netinstall-2404` → `roles/pxe-2404`
- [ ] Plays renamed and all `utils/pb` invocation docs/comments updated
- [ ] Cross-role file reference updated: `roles/netinstall-2404/tasks/pxe.yml` copies `../../netinstall/files/pxeboot/` — must follow the rename
- [ ] Decision recorded on variable/tag prefix: keep `ni_*` (churn-free) or rename to `pxe_*` in the same pass
- [ ] **Served paths and URLs are explicitly out of scope for the first pass**: `/srv/netinstall`, `/var/www/html/netinstall`, and the `http://pxe.cttb/netinstall/` tree are baked into live `pxelinux.cfg/default`, `grub/grub.cfg`, autoinstall `ds=`/`url=` kernel args, and the hand-maintained dnsmasq `dhcp-boot=` lines (#69). Renaming those requires a coordinated cutover and its own issue.
- [ ] Full-run check: `utils/pb <renamed-play> --check` completes against `cttb_pxe`

## Workaround

None needed — the current names work; this is naming hygiene.

## Where to look first

`roles/netinstall-2404/tasks/pxe.yml` (the `../../netinstall/files/pxeboot/` relative copy is the one cross-role coupling that breaks silently if missed).

## Context

Requested 2026-08-06 mid-session while regenerating the pxe.cttb homepage; deferred to keep that goal scoped. The homepage/role work repeatedly shows the naming mismatch (host says pxe, repo says netinstall). Recommendation: rename repo objects only; leave on-server paths and URLs untouched until a coordinated cutover.
