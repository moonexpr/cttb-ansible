# pxe24: "two MAC addresses on one ethernet adapter" — investigation

**Date:** 2026-07-30 · **Status:** RESOLVED — Option B applied same day (see
"Resolution applied" below; gh-106) · **Host:** `pxe24` LXC on **srv-nas**
(10.11.1.5)

> The question arrived as "pxe24 on srv-nav". `srv-nav` does not exist —
> not in inventory, DNS, or git history. The host is `srv-nas`.

## TL;DR

pxe24's `eth0` has exactly **one real MAC**: `00:16:3e:8c:80:b6`
(LXD-random `volatile.eth0.hwaddr`; no static `hwaddr` pinned). What looks
like "two MACs on one adapter" is **two identities the network associates
with that one adapter**, plus **two IPv4 addresses** it briefly carries:

| Identity | Where it lives | Reality |
|---|---|---|
| `00:16:3e:11:01:23` (reserved) | `/etc/dnsmasq-hosts/servers:19` (`lxc-pxe`), `host_vars/srv-nas` | Belongs to the **legacy `pxe` container**, still present on srv-nas but **STOPPED** since the 2026-05-12 cutover. pxe24 took over the IP, never the MAC. |
| `00:16:3e:8c:80:b6` (actual) | `lxc config show pxe24` → `volatile.eth0.hwaddr` | Answers ARP for 10.11.1.23 today; PXE/HTTP serving fine (HTTP 200). |

| Address on eth0 | Source | Reality |
|---|---|---|
| `10.11.1.23/16` | static netplan (`/etc/netplan/50-cloud-init.yaml`, `dhcp4: false`, unchanged since 2026-05-13) | The intended pxe.cttb address. |
| `10.11.13.122/16` | dynamic 48 h dnsmasq lease, quarantine pool | Acquired 2026-07-30 21:48 UTC; flagged `secondary dynamic`. **Self-expires ~2026-08-01 21:48 UTC** — the current config has no DHCP client to renew it. |

MAC-encodes-IP convention reference: `docs/infrastructure-diagram.md`
("`00:16:3e:11:01:XX` where `XX` = last octet").

## Timeline (evidence from the box)

| When (UTC) | Event |
|---|---|
| 2026-05-12 | `/etc/netplan/50-cloud-init.yaml.bak` shows the original `dhcp4: true` (LXD default) — pxe24 was born as a DHCP client in quarantine (10.11.13.27, the address that fossilized in `cttb-ct.sh` until this fix). |
| 2026-05-12/13 | Cutover: legacy `pxe` (16.04 box → container) stopped; pxe24 re-IP'd in place to static 10.11.1.23 (`.pxe-cutover-bak` preserved). |
| Jul 25–29 | systemd-networkd restarted mid-uptime (pid 9487 → 264); "DHCPv6 lease lost" events — DHCP clients ran despite the on-disk static config. OS hostname is still **`pxetest`**: the container was built as a test box and repurposed. |
| Jul 30 21:48 | `netplan apply` regenerated `/run/systemd/network/10-netplan-eth0.network` (static-only, no DHCP stanza) — **the same minute** dnsmasq issued the 10.11.13.122 lease to a systemd-networkd DUID-style client-id embedding pxe24's MAC. |
| Jul 30 21:58 | dnsmasq **renewed the reserved-MAC lease** `00:16:3e:11:01:23` → 10.11.1.23 (`lxc-pxe`) — while the legacy `pxe` container was stopped. Something on the box *presented the reserved MAC* ten minutes after the netplan apply. |

**Conclusion:** an experimentation session on Jul 30 (operator or agent,
testing MAC/netplan changes on pxe24) transiently ran DHCP. The unregistered
random MAC landed in the quarantine pool (10.11.13.122); the reserved MAC was
presented separately and refreshed the `lxc-pxe` lease. From dnsmasq's view
the one PXE adapter therefore showed **two active MAC identities within ten
minutes** — the observation that prompted this investigation. The static
config was then re-applied; the stray dynamic address lingers only until its
kernel lease lifetime expires.

## Repo drift corrected alongside this doc

- `host_vars/srv-nas` — `lxc_containers` still declared only the legacy
  `pxe` entry (reserved MAC) with no mention of pxe24. Annotated (comments
  only; no functional change, so no Ansible run will act on it).
- `.claude/sysadmin/cttb-ct.sh` `NAS_CTS` — `pxe24` row pointed at the dead
  quarantine address 10.11.13.27. Now `pxe24 → 10.11.1.23`; `pxe` marked
  stopped/legacy.

## Resolution applied (2026-07-30, gh-106) — Option B + legacy retirement

Operator direction: deprecate the old `pxe`, repin the PXE IP onto the new
container's MAC. Applied same day:

1. **Legacy container retired.** On srv-nas: `lxc move pxe pxe-deprecated`
   (stopped, no autostart, data kept for rollback). The reserved MAC
   `00:16:3e:11:01:23` is retired with it.
2. **Reservation repinned.** On lxc-dnsmasq,
   `/etc/dnsmasq-hosts/servers` line 19 is now
   `00:16:3e:8c:80:b6,10.11.1.23,lxc-pxe24` (backup:
   `servers.bak-20260730` alongside). `dnsmasq --test` passed; dnsmasq
   restarted; the restart also pruned the stale `00:16:3e:11:01:23` lease.
   This is a **deliberate exception** to the MAC-encodes-IP convention.
3. **Post-checks.** DNS resolving (wiki.cttb OK), PXE HTTP 200,
   `ip neigh` for 10.11.1.23 answers from the registered MAC.
4. **Repo aligned.** `host_vars/srv-nas` now declares `pxe24` with the
   real hwaddr (legacy `pxe` entry removed so `roles/virt` can never
   recreate it); `cttb-ct.sh` NAS_CTS updated.

Rollback: restore `servers.bak-20260730` + restart dnsmasq;
`lxc move pxe-deprecated pxe` if the old container is ever needed.

## Remaining follow-ups

- After 2026-08-01 21:48 UTC: `sudo lxc exec pxe24 -- ip -4 addr show eth0`
  on srv-nas should show only 10.11.1.23 (the quarantine lease
  10.11.13.122 self-expires). If still present, something is renewing it —
  reopen gh-106.
- Once confirmed stable: delete `pxe-deprecated` to reclaim disk.
- Cleanup candidate: container OS hostname `pxetest` ≠ LXD name `pxe24`.
- Optional forensics: `/root/.bash_history` on srv-nas for the Jul 30 test
  session.
