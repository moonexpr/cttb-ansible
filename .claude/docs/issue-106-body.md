## Repro

```bash
# actual MAC on the live container (srv-nas)
ssh administrator@srv-nas -- sudo lxc config show pxe24 | grep hwaddr
#   volatile.eth0.hwaddr: 00:16:3e:8c:80:b6      # LXD-random, no static hwaddr

# reservation on the DHCP side (lxc-dnsmasq on srv-vm)
ssh srv-vm -- lxc exec dnsmasq -- grep 11:01:23 /etc/dnsmasq-hosts/servers
#   00:16:3e:11:01:23,10.11.1.23,lxc-pxe
```

On 2026-07-30 dnsmasq simultaneously held active leases for **both** MACs —
`00:16:3e:8c:80:b6 → 10.11.13.122` (quarantine) and
`00:16:3e:11:01:23 → 10.11.1.23` (lxc-pxe) — i.e. one PXE adapter, two DHCP
identities.

## Expected

The container serving `pxe.cttb` (10.11.1.23) presents the reserved
convention MAC `00:16:3e:11:01:23` (site rule: MAC encodes the last octet),
and only that identity appears in dnsmasq.

## Actual

`pxe24` took over the legacy `pxe` container's IP at the 2026-05-12 cutover
(#6) but never its MAC. The legacy `pxe` container still exists on srv-nas
(STOPPED) holding the reserved MAC in config. A Jul 30 test session
transiently ran DHCP on pxe24, landing a stray quarantine address
(10.11.13.122, self-expires ~2026-08-01 21:48 UTC) and refreshing both
lease identities within ten minutes.

## Repo locations

- `/Users/jc/GitRepos/cttb-ansible/docs/pxe24-two-macs-investigation.md` — full findings + timeline
- `/Users/jc/GitRepos/cttb-ansible/host_vars/srv-nas` — legacy `pxe` entry (annotated), no `pxe24` entry yet
- `/Users/jc/GitRepos/cttb-ansible/.claude/sysadmin/cttb-ct.sh` — NAS_CTS table (corrected)

## Acceptance criteria

- [x] One remediation chosen and applied: **Option B** (+ legacy container renamed `pxe-deprecated`)
  - **Option A (convention-restoring):** pin `hwaddr=00:16:3e:11:01:23` on pxe24's eth0 (one restart) **and** permanently retire the stopped legacy `pxe` container so it can never re-claim the MAC/IP; or
  - **Option B (low-touch):** update `/etc/dnsmasq-hosts/servers` to map 10.11.1.23 → `00:16:3e:8c:80:b6` (accepts a permanent convention exception).
- [x] dnsmasq shows exactly one MAC identity for 10.11.1.23; `ip neigh` for 10.11.1.23 matches the registered MAC.
- [x] `host_vars/srv-nas` gains a real `pxe24` entry reflecting the chosen MAC (drift note removed).
- [ ] Stray 10.11.13.122 confirmed gone from pxe24's eth0 after 2026-08-01 21:48 UTC.
- [ ] (nice-to-have) container OS hostname `pxetest` renamed to `pxe24`.

## Workaround

None needed — PXE/HTTP serve fine today (ARP for 10.11.1.23 answers from the
real MAC; HTTP 200). This is convention/records drift, not an outage.

## Where to look first

`sudo lxc config device override pxe24 eth0 hwaddr=...` on srv-nas (Option A)
vs `/etc/dnsmasq-hosts/servers` on lxc-dnsmasq (Option B). Findings doc has
the trade-offs.

## Context

Surfaced while investigating "why does pxe24 have two MACs on one ethernet
adapter" (2026-07-30). pxe24 originated as `pxetest` (#6) and was promoted by
IP takeover; the MAC side of the takeover was never done, so the reserved MAC
still belongs to the stopped legacy container and the live one runs on an
LXD-random MAC — unregistered, hence its excursions into the quarantine pool.

