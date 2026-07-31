# dnsmasq

Campus DHCP server, PXE `dhcp-boot` pointer, and local-authority DNS for
the `cttb` domain — the service that runs on `lxc-dnsmasq` (`10.11.1.19`,
`dnsmasq.cttb`).

## What this box actually is

`dnsmasq.cttb` is three services in one process:

1. **The campus DHCP server.** ~1,100 active leases across the
   `10.11.0.0/16` static range plus the `block13` dynamic ranges
   (`10.11.13.x`, `10.11.130.x`) for unregistered machines. It is
   `dhcp-authoritative`.
2. **The PXE `dhcp-boot` pointer.** It hands UEFI clients `grubx64.efi`
   and BIOS clients `pxelinux.0`, both fetched from the PXE/TFTP server
   (`dnsmasq_pxe_server`, currently the pxe24 LXC at `10.11.1.23`). It
   does not serve TFTP itself.
3. **Local-authority DNS.** It answers `*.cttb` from its DHCP host
   database and `host-record` lines, and is the enforcement point for
   the content-filter split: DHCP option 6 hands `block13`, `girl9`,
   `boy10`, `adultnm` and `asterisk6` clients different resolvers.

It is *not* a recursive resolver. `dnsmasq.conf` carries `no-resolv` and
no `server=`; clients recurse via the resolver they get in DHCP option 6
(`10.11.1.29`, ub-adult). The one exception — and the reason this role
exists — is below.

## The upstream gap (cttb-ansible#89)

Because the main config has `no-resolv` and no `server=`, any client that
queries `.19` *directly* instead of using DHCP option 6 gets a walled
garden: campus names resolve, the internet does not. This surfaced on
2026-05-19 when two Macs on the Earth Store Hall AP did exactly that.

The fix is `/etc/dnsmasq.d/upstream.conf` (`server={{ dnsmasq_upstream }}`),
which this role owns. Keeping it in Ansible is the point: the gap existed
for years precisely because the upstream lived nowhere durable.

## What the role manages

- The `dnsmasq` package.
- `/etc/dnsmasq.conf` from `templates/dnsmasq.conf.j2` — the recovered
  authoritative config (== the `pre-pxetest-20260512` known-good
  backup), with the PXE/TFTP address as the single variable
  `dnsmasq_pxe_server` (closes cttb-ansible#69). Installed with
  `validate: dnsmasq --test` so a broken render never lands.
- `/etc/dnsmasq.d/upstream.conf` — the Ansible-owned upstream (#89).
- The `dhcp-hostsdir` directory. **Not its contents** — see below.
- The enabled `systemd` unit, plus a post-deploy resolution + DHCP
  sanity check.

## What the role does NOT manage: the hosts database

`/etc/dnsmasq-hosts/` (`adult`, `boys`, `girls`, `devices`, `printers`,
`drbu`, …) is the DHCP host→IP/tag database. Its content is maintained
out of band in the dnsmasq config git repo (`~/Garden/external/dnsmasq`,
`/home/administrator/dnsmasq.git` on-box) through Rui's `register.py` /
`next-ip.py` workflow. The deployed set and the git set have drifted
(deployed: 6 files; git tracks 15). Reconciling that and deciding the
source of truth is tracked in cttb-ansible#89 and `TODO.md`; until then
`dnsmasq_manage_hosts_content` defaults to `false` and the role only
guarantees the directory.

## Variables

See `defaults/main.yml`. The ones you are most likely to set:
`dnsmasq_upstream`, `dnsmasq_pxe_server`, `dnsmasq_client_dns`,
`dnsmasq_log_queries`.

## Deploying

`plays/deploy-dnsmasq.yml`. This role targets the **24.04 replacement**
container only — the legacy 16.04 box has Python 3.5 and cannot run
these modules. Standing up that container and the IP-takeover cutover
are the runbook's job: `docs/dnsmasq-24.04-migration.md` (cutover is
gated and not performed by this role or play).

## Related

- cttb-ansible#89 — upstream gap + Ansible coverage + git/deployed drift
- cttb-ansible#69 — `dhcp-boot` PXE-server IP as a single variable
- cttb-ansible#47 — Unbound↔dnsmasq `cttb.` zone duplication
- `roles/unbound` — the recursive resolver (`ub-adult`, `10.11.1.29`)
  that this box forwards to and hands clients via option 6.
