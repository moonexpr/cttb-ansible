# dnsmasq 16.04 → 24.04 migration runbook

**Status:** prepared, **cutover NOT executed**. Tracking: cttb-ansible#89.
**Pattern:** fresh 24.04 LXC + IP takeover — the same play run for pxe24
on 2026-05-12 (see the `[pxe-server]` note in
`inventory/sudhanix26_hosts.ini`).
**Author/date:** prepared 2026-05-19 during the Earth Store Hall
walled-garden incident.

---

## 1. Why a rebuild and not an in-place upgrade

`lxc-dnsmasq` is Ubuntu **16.04.7** (EOL; apt repos moved to
`old-releases.ubuntu.com`) and ships **Python 3.5**, which modern
Ansible modules cannot run — `plays/deploy-netinstall-2404.yml` already
works around this with `raw` throughout. An in-place
`do-release-upgrade` would be four sequential hops on a live campus
DHCP/DNS server with rollback only via container snapshot (and there is
**no** snapshot — `lxc info dnsmasq` shows none). The proven campus move
is to build the replacement clean on 24.04 and take over the IP, which
gives an instant rollback (re-IP the old box back) and lands the config
under Ansible (`roles/dnsmasq`) on the way.

## 2. What must survive the move

| Surface | Source of truth | Handling |
|---|---|---|
| `dnsmasq.conf` (DHCP ranges, dhcp-boot, options, `no-resolv`) | deployed `/etc/dnsmasq.conf` (== `…pre-pxetest-20260512`, 351 lines) → `roles/dnsmasq/templates/dnsmasq.conf.j2` | Ansible |
| Upstream resolver | `/etc/dnsmasq.d/upstream.conf` (`server=10.11.1.29`) | Ansible (`roles/dnsmasq`, #89) |
| Identity | IP `10.11.1.19`, `dnsmasq.cttb` | IP takeover at cutover |
| DHCP host DB | `/etc/dnsmasq-hosts/` (6 files live; git tracks 15) | **out of band** — ported manually, drift unresolved (#89) |
| Active leases | `/var/lib/misc/dnsmasq.leases` (~1,120) | copied once at cutover |
| dhcp-boot target | `dnsmasq_pxe_server` = `10.11.1.23` (pxe24) | role variable (#69) |

The hosts DB and the dead backup peer `lxc-bk-dnsmasq` (`10.11.1.86`,
unreachable — Vincent's rsync silently failing) are the two soft spots.
Resolve drift (#89) **before** cutover or accept the live set as truth.

## 3. Pre-flight (no production impact)

1. Confirm the stopgap from the 2026-05-19 incident is in place and the
   service is healthy on the old box:
   - `systemctl is-active dnsmasq` → `active`; `is-enabled` → `enabled`
   - lease-file mtime advancing (DHCP serving)
   - `dig @10.11.1.19 google.com` and `… wiki.cttb` both resolve
2. Snapshot the inputs off-box: copy the live `/etc/dnsmasq.conf`,
   `/etc/dnsmasq.d/upstream.conf`, the whole `/etc/dnsmasq-hosts/`, and
   the current `dnsmasq.leases` to a dated dir. Commit the conf+hosts
   into `~/Garden/external/dnsmasq` so git matches reality (closes the
   drift item, or at minimum records it).
3. Resolve the #89 drift decision (repo vs box canonical). Record it in
   `roles/dnsmasq/TODO.md`.

## 4. Build the 24.04 container (parallel, no impact)

1. Provision a 24.04 LXC on `srv-vm` (the dnsmasq host) using the same
   mechanism pxe24 used. Give it a **temporary** IP (e.g. `10.11.1.x`
   free) and a name like `dnsmasq-2404`. Do **not** put it on
   `10.11.1.19` yet.
2. Add it to `inventory/sudhanix26_hosts.ini` under a `dnsmasq_target`
   group with its temp IP. (A throwaway `dnsmasq-scratch` host in the
   same group is the validation target for step 5.)
3. Seed `/etc/dnsmasq-hosts/` on the new box from the snapshot in step
   3.2 (or from the git repo once drift is resolved).

## 5. Validate the role against a scratch container (gate)

This is the cttb-ansible#89 acceptance gate — do it before touching the
real replacement:

```bash
ansible-playbook plays/deploy-dnsmasq.yml \
  -i inventory/sudhanix26_hosts.ini -l dnsmasq-scratch --syntax-check
ansible-playbook plays/deploy-dnsmasq.yml \
  -i inventory/sudhanix26_hosts.ini -l dnsmasq-scratch --check --diff
ansible-playbook plays/deploy-dnsmasq.yml \
  -i inventory/sudhanix26_hosts.ini -l dnsmasq-scratch
```

Pass criteria on the scratch box:

- `dnsmasq --test -C /etc/dnsmasq.conf` → OK (the role's `validate:`
  already enforces this; confirm independently).
- `systemctl is-active dnsmasq` → active; `is-enabled` → enabled;
  **survives `lxc restart dnsmasq-scratch`** (reboot-persistence — the
  property the hand-run stopgap lacked).
- `dig @<scratch-ip> google.com` resolves (proves upstream snippet).
- `dig @<scratch-ip> wiki.cttb` → `10.11.1.34`.
- With a test client on an isolated bridge: it gets a lease, the
  correct option 6, and PXE `dhcp-boot` points at `dnsmasq_pxe_server`.

## 6. Cutover window — GATED, NOT performed by prep

> Requires explicit go. Campus DHCP/DNS interruption ≈ the swap time
> (seconds to a couple of minutes). Schedule low-traffic.

1. Freeze: ensure no in-flight registrations (`register.py`).
2. On the old box: `systemctl stop dnsmasq`.
3. Copy the **final** `/var/lib/misc/dnsmasq.leases` and any
   `/etc/dnsmasq-hosts/` deltas from old → new (last-moment sync so
   active leases carry over and clients keep their IPs).
4. Re-IP: remove `10.11.1.19` from the old container's `eth0`; assign
   `10.11.1.19` to `dnsmasq-2404`'s `eth0` (mirror the pxe24 re-IP
   step). DNS `dnsmasq.cttb` → `10.11.1.19` is unchanged, so every
   hardcoded downstream ref (option 6 targets, dhcp-boot, lab refs)
   follows automatically — no client reconfiguration.
5. Start: `systemctl start dnsmasq` on the new box.
6. Verify within the window (same checks as §5, plus): lease-file
   mtime advancing on the **new** box; a real client renews; PXE boot
   a test machine end to end.

## 7. Rollback (instant)

If §6 verification fails: `systemctl stop dnsmasq` on the new box,
re-assign `10.11.1.19` back to the old 16.04 container, `systemctl
start dnsmasq` there. Old box is untouched and still has its leases —
this is why the old container is kept, not destroyed, until §8.

## 8. Post-cutover

- Soak 48 h (one full lease cycle) watching lease churn and resolution.
- Move `inventory` `dnsmasq_target` to the new box on `10.11.1.19`;
  retire the temp IP and the `dnsmasq-scratch` host.
- Only then decommission the old 16.04 container (keep a final tarball
  of its `/etc` and leases).
- Stand up the SP-Monitoring alert: `:53` external-name failure **and**
  lease-file-mtime-stalled (the DHCP-down detector this incident
  proved we lacked).
- Re-home or delete `lxc-bk-dnsmasq`; the hosts-DB backup must be git,
  not a dead peer.

## 9. Open risks carried into cutover

- **`--local-service`.** The unit runs with it (DNS answered only to
  local-subnet sources). The role’s upstream snippet fixes recursion
  but not reachability — if the Earth Store Hall AP (or any segment
  hitting `.19` directly) is routed from another subnet,
  `--local-service` still drops it. Decide before cutover; see
  `roles/dnsmasq/TODO.md`.
- **Hosts-DB drift (#89).** If unresolved at cutover, the live
  `/etc/dnsmasq-hosts/` is authoritative by default and the richer
  git set is shelved — record the decision, don't let it be implicit.
- **No old-box snapshot.** Rollback depends on the old container
  staying intact through §8. Do not delete early.
