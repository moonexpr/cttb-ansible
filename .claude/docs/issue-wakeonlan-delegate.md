`plays/util-wakeonlan.yml` sends its magic packets from the Ansible controller (`delegate_to: localhost`). When the controller is not on the campus L2 — the normal case for a sysadmin working from a laptop over Tailscale — the broadcast never reaches the target segment. The play still reports `changed=2, failed=0`, so it looks like it worked.

A wake that silently does nothing is worse than one that errors: the operator concludes the target's WoL is broken, or that the machine is dead, and goes to the room.

## Repro

From a controller that reaches campus via the Tailscale subnet router rather than campus Ethernet:

```bash
# terminal 1 — watch the campus segment from any on-campus host
ssh administrator@dvgs-lab3.cttb 'sudo tcpdump -i enp2s0 -nn "udp port 9 or udp port 7"'

# terminal 2 — fire the play from the laptop
utils/pb util-wakeonlan --limit drbu-sw-cslab-w-pc3.cttb
```

## Expected

Magic packets arrive on the campus segment and the target wakes.

## Actual

Verified 2026-08-06 from a macOS controller reaching `10.11.0.0/16` over `utun4` (Tailscale):

```
PLAY RECAP
drbu-sw-cslab-w-pc3.cttb  : ok=2  changed=2  unreachable=0  failed=0

=== capture on the campus segment during that run ===
0 packets captured
```

**Control**, same capture, packet sent from an on-campus host — proving the capture itself works:

```
18:03:48.110442 IP 10.11.9.23.57424 > 255.255.255.255.9:   UDP, length 102
18:03:48.121221 IP 10.11.9.23.34726 > 10.11.255.255.9:     UDP, length 102
2 packets captured
```

Same target MAC, same play semantics — the only difference is where the packet originates. Sending from `dvgs-lab3.cttb` woke `drbu-sw-cslab-w-pc3.cttb` in ~50 s; sending from the laptop produced nothing on the wire.

## Root cause

`plays/util-wakeonlan.yml:8-13`:

```yaml
- name: Send WoL packet 1
  community.general.wakeonlan:
    mac: "{{ mac_addr }}"
  delegate_to: localhost
```

A WoL magic packet is an L2 broadcast (default `255.255.255.255:9`). It is not routable and does not traverse the Tailscale tunnel — the controller sends it out its own default interface, onto the operator's home/office LAN, where nothing is listening. The module has no way to detect this: it wrote to a socket successfully, so it reports `changed`.

Campus is a flat `10.11.0.0/16` (confirmed: `10.11.0.0/16 dev enp2s0` on `dvgs-lab3`), so *any* on-campus host is a valid sender for *any* campus target — no per-VLAN sender table is needed.

## Repo locations

- `plays/util-wakeonlan.yml:8-13` — both tasks pinned to `delegate_to: localhost`
- `utils/pb:4` — the documented invocation (`utils/pb util-wakeonlan -l drbu_cs_lab`) inherits the defect
- `inventory/sudhanix26_hosts.ini` — `mac_addr=` is correct; not implicated

## Acceptance criteria

- [ ] The magic packet originates from a host on the campus L2, not from the controller
- [ ] The sender is configurable (e.g. `wol_sender`, defaulting to a stable always-on campus host such as `srv-vm`) rather than hardcoded
- [ ] Running the play from an off-campus controller wakes the target, or fails loudly if no sender is reachable — it must not report success having sent nothing
- [ ] The tcpdump repro above shows packets on the campus segment when run from a laptop

## Workaround

Send from any on-campus host:

```bash
ssh administrator@dvgs-lab3.cttb 'wakeonlan 3C:D9:2B:78:FF:BA; wakeonlan -i 10.11.255.255 3C:D9:2B:78:FF:BA'
```

`wakeonlan` is already installed on the lab desktops.

## Where to look first

Change `delegate_to: localhost` to a campus sender. The only judgement call is which host to make the default — it must be always-on and on `10.11.0.0/16`. `srv-vm` (10.11.1.3) is the obvious candidate; a lab desktop is not, since the lab desktops are exactly the machines being woken.

## Context

Found 2026-08-06 while smoke-testing wake-on-LAN, remote screenshot, and pamtester against `drbu-sw-cslab-w-pc3.cttb`. WoL itself is fine — the target's NIC honors the magic packet and the inventory MAC is correct. Only the delivery path is wrong, and only for controllers off the campus L2. Anyone running this from a machine plugged into campus Ethernet would never see the failure, which is likely why it has gone unnoticed.
