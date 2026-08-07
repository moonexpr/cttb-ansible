Wake-on-LAN cannot be relied on anywhere on the lab fleet. The desktops' NICs support magic-packet wake but ship with it **disabled at the driver level**, and nothing in this repo arms it or persists the setting. A host that is shut down cleanly from Linux cannot be woken remotely at all — it needs someone to walk to the room and press the power button.

This is the reason wake-on-LAN "sometimes works": a machine that lost power, or was powered off in a state that left the NIC armed, will wake. One clean `systemctl poweroff` later, it will not.

## Evidence

Verified 2026-08-06 on `drbu-sw-cslab-w-pc2.cttb` (10.11.16.14), same lab and configuration as pc3:

```
$ sudo ethtool eno1 | grep -i wake-on
	Supports Wake-on: pumbg      <- 'g' = magic packet IS supported
	Wake-on: d                   <- but it is DISABLED
```

No persistence anywhere — no `WakeOnLan=` in `/etc/systemd/network/`, no `ethtool.wake-on-lan` in NetworkManager, no ethtool unit:

```
$ grep -rl "wol\|WakeOnLan" /etc/systemd/network/ /etc/NetworkManager/
(no matches)
```

## Repro / demonstration

`drbu-sw-cslab-w-pc3.cttb` (10.11.16.15, MAC `3c:d9:2b:78:ff:ba`) on 2026-08-06:

1. Found powered off. A magic packet sent from an on-campus host woke it in ~50 s. **WoL hardware and BIOS config are fine.**
2. Shut down with `systemctl poweroff` (0 user sessions).
3. Every subsequent wake attempt failed, across every variation:

| Attempt | Result |
|---|---|
| UDP `255.255.255.255`, port 9, from a lab desktop | no wake |
| UDP `255.255.255.255`, port 7 | no wake |
| UDP `10.11.255.255`, port 9 | no wake |
| UDP from srv-vm (10.11.1.3), both forms | no wake |
| UDP from pc2 (10.11.16.14) — same L2 segment | no wake |
| Raw L2 frame, EtherType `0x0842`, 116 bytes, ×3, from pc2 | no wake |

**Delivery is not the problem.** `tcpdump` on `eno1` of pc2 — the same broadcast domain as pc3 — captured the packets arriving:

```
18:34:20.238800 IP 10.11.1.3.51541 > 255.255.255.255.7: UDP, length 102
18:34:20.238977 IP 10.11.1.3.51541 > 255.255.255.255.9: UDP, length 102
18:34:20.239058 IP 10.11.1.3.51541 > 10.11.255.255.7:   UDP, length 102
18:34:20.239271 IP 10.11.1.3.51541 > 10.11.255.255.9:   UDP, length 102
4 packets captured
```

The packets reach the wire in front of the target and the target ignores them. That isolates the fault to the NIC's armed state.

pc3 is currently powered off and **not remotely recoverable**; it needs a physical power-on.

## Expected

A lab desktop shut down by any normal means can be woken by `utils/pb util-wakeonlan`.

## Actual

Wake works only by accident of the prior power state. After a clean shutdown the machine is unreachable until someone presses the button.

## Repo locations

- `roles/common/tasks/setup/default.yml:380,390,448` — the existing `wake_on_lan` references and the `wakeonlan` package install; these set up the *sender* side, not the *receiver* arming
- `plays/util-wakeonlan.yml` — the sender play (delivery path fixed separately in #116)
- No role currently manages `ethtool`/`WakeOnLan=` state on the desktops — that is the gap

## Acceptance criteria

- [ ] Lab desktops persist magic-packet wake across reboots and clean shutdowns — `ethtool <iface> | grep Wake-on` reports `g`, not `d`
- [ ] The setting is applied by a role, not by hand, and survives re-provisioning / PXE reinstall
- [ ] A host shut down with `systemctl poweroff` can subsequently be woken by `utils/pb util-wakeonlan`
- [ ] Interface naming is not hardcoded — lab desktops vary (`eno1`, `enp2s0` both seen in this fleet)
- [ ] Decide whether to arm the whole fleet or only hosts in a designated group

## Where to look first

The netplan/systemd-networkd route is the most durable, since it re-applies on every boot and does not depend on a shutdown hook firing:

```
# /etc/systemd/network/10-wol.link
[Match]
Type=ether

[Link]
WakeOnLan=magic
```

Alternatives: a NetworkManager connection property (`ethtool.wake-on-lan magic`) if NM manages the link, or a `systemd` oneshot running `ethtool -s <iface> wol g`. Whichever is chosen, verify against a real clean shutdown — the failure mode here is specifically that the flag is lost at power-off, so a check that only runs while the host is up proves nothing.

Worth confirming on one machine by hand before rolling out, since the wrong answer leaves hosts that cannot be recovered remotely.

## Context

Found 2026-08-06 while verifying the fix for #116. #116 is about the magic packet never leaving the controller; this issue is about the packet arriving and being ignored. Both had to be true for wake-on-LAN to appear "broken", and fixing #116 alone would not have woken a single cleanly-shut-down host.
