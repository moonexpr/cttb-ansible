## Repro

On `lxc-dnsmasq` (10.11.1.19), the option that routes a population to the filtering resolver is present:

```bash
$ ssh srv-vm 'lxc exec dnsmasq -- grep -rn adultnm /etc/dnsmasq.conf /etc/dnsmasq.d/ /etc/dnsmasq-hosts/'
/etc/dnsmasq.conf:109:dhcp-option=tag:adultnm,6,10.11.1.28
```

That is the **only** occurrence anywhere in the dnsmasq configuration. Nothing sets the tag:

```bash
$ ssh srv-vm 'lxc exec dnsmasq -- grep -rhoE "set:[a-z0-9]+" /etc/dnsmasq-hosts/ | sort | uniq -c | sort -rn'
    170 set:sw12
    117 set:girl9
    115 set:boy10
    109 set:asterisk6
      5 set:tftp
      2 set:obihai18
```

(Counts include the ignored `devices~` / `servers.bak-*~` files; excluding those the real figures are `sw12` 149, `girl9` 111, `asterisk6` 108, `boy10` 95, `tftp` 5, `obihai18` 1. `adultnm` is zero either way.)

## Expected

A device intended to receive the filtered resolver `ub-igdvs` (10.11.1.28) is tagged `adultnm` in `/etc/dnsmasq-hosts/`, and dnsmasq hands it DHCP option 6 = 10.11.1.28.

## Actual

No host entry carries `set:adultnm`, so `dhcp-option=tag:adultnm,6,10.11.1.28` never matches any client. The rule has no effect. The filtered resolver is reached only by the `girl9` (111) and `boy10` (95) tags — **206 devices** — while every other device on campus, including the entire `adult` file (3,806 entries), receives the default `dhcp-option=6,10.11.1.29` (`ub-adult`, the permissive resolver).

No failure signature is emitted: dnsmasq does not warn about an option whose tag is never set, which is why this has gone unnoticed.

## Repo locations

- `/etc/dnsmasq.conf:109` on `lxc-dnsmasq` — the live, un-templated config (out of Ansible coverage, see #89)
- `/Users/jc/GitRepos/cttb-ansible/roles/dnsmasq/templates/dnsmasq.conf.j2` — the staged template, which reproduces the same `tag:adultnm` line
- `/etc/dnsmasq-hosts/` on the box — the host database that would need the tag applied; not in version control (#89)

## Acceptance criteria

- [ ] A decision is recorded on whether an `adultnm` population should exist at all, and if so which devices belong to it.
- [ ] Either the devices are tagged and verified to receive 10.11.1.28, **or** the `tag:adultnm` option line is removed from both the live config and `roles/dnsmasq/templates/dnsmasq.conf.j2`.
- [ ] `grep -c 'tag:adultnm' /etc/dnsmasq.conf` and `grep -rc 'set:adultnm' /etc/dnsmasq-hosts/` agree — either both non-zero, or both zero.
- [ ] The same audit is applied to `set:sw12` (149 devices) and `set:obihai18` (1), which are set on host entries but have no matching `dhcp-option` anywhere — tagged and ignored, the mirror image of this bug.

## Workaround

None required for correctness of the current network; the effect is that a population which may have been intended for DNS-layer filtering is not being filtered. To place a device on the filtering resolver today, tag it with an already-wired tag or add an explicit per-host option.

## Where to look first

`roles/dnsmasq/templates/dnsmasq.conf.j2`, the option block around the per-tag resolver split (`girl9`, `boy10`, `adultnm`, `asterisk6`). The template is a faithful capture of the live file, so whatever is decided has to change in both until the role is actually deployed against a host — `plays/deploy-dnsmasq.yml` targets a `dnsmasq_target` group that exists in neither inventory.

## Context

Found on 2026-08-01 while surveying live DNS/DHCP for the BIND 9 + ISC Kea migration proposal ([IT:DNS Migration Proposal](http://wiki.cttb/wiki/IT:DNS_Migration_Proposal)). The survey was auditing which tags actually drive behaviour so they could be translated into Kea client classes, and `adultnm` turned out to translate to nothing.

Worth treating on its own account rather than as migration cleanup: `adultnm` reads as "adult, non-monastic", which suggests it was meant to place a specific resident population behind the stricter resolver used by the schools. If that was the intent, the filtering has been absent for an unknown period. Confirming the intent is a content-policy question for whoever owns filtering, not something the migration should silently resolve by dropping the line.

Related: #89 (the same box has no Ansible coverage and its host database is not in version control, which is why drift like this is invisible).
