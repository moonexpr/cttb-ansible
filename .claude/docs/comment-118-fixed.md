Root cause found, fixed, and verified end-to-end on `drbu-sw-cslab-w-pc2.cttb`.

**Correction to this issue's body.** I wrote that nothing in the repo arms WoL. That was wrong: `roles/common/tasks/setup/default.yml` has shipped `/etc/NetworkManager/conf.d/ethernet-wake-on-lan.conf` with `ethernet.wake-on-lan = 64` for some time, and it was deployed and correct on the host. My grep looked for `WakeOnLan=`/`wol` and missed it. The setting simply never took effect, which is the more interesting finding.

**Why it never took effect.** netplan generates the NetworkManager keyfile and writes the property *explicitly*:

```
$ cat /run/NetworkManager/system-connections/netplan-id0.nmconnection
[ethernet]
wake-on-lan=0        <- NM_SETTING_WIRED_WAKE_ON_LAN_NONE
```

A `conf.d` `[connection]` entry only supplies a default for properties the profile leaves unset. This profile sets it explicitly to `0`, so the global `64` was never consulted. `nmcli` reports the property as `--`, which reads like "unset" and hides the problem.

This also explains a false lead: a udev `.link` with `WakeOnLan=magic` *is* applied (`ID_NET_LINK_FILE` confirms the match), and the flag still ends up `d` — NetworkManager re-applies `wake-on-lan=0` when it activates the connection, after udev has armed the NIC.

**Fix** (commit on `main`): a netplan drop-in setting `wakeonlan: true` on the cloud-init `id0` ethernet. netplan then emits `wake-on-lan=1` — NM's `DEFAULT`, not `NONE` — which lets the existing `conf.d` value of 64 (magic) apply. The `.link` is kept for hosts where udev/networkd owns the link rather than NM.

**Verification on pc2:**

1. Before: `Wake-on: d`.
2. After the drop-in + `netplan generate` + reboot: `Wake-on: g`, persisting across the boot.
3. `systemctl poweroff`, then `utils/pb util-wakeonlan --limit drbu-sw-cslab-w-pc2.cttb` from a macOS controller reaching campus over Tailscale → **the host woke in ~45 s**.

That is the full path working: off-campus controller → on-campus sender (#116) → armed NIC (this issue) → powered-on host.

**Operational note worth keeping.** The NIC is not armed the instant the host drops off the network. A magic packet sent immediately after `poweroff` is missed; the same packet ~2 minutes later woke it. Anything that scripts shutdown-then-wake should allow for that settling time, and a single failed wake attempt is not evidence that WoL is broken.

**Not yet done:** this is applied to pc2 only. The rest of the fleet still boots with `Wake-on: d` until the `wake_on_lan` tag is deployed more widely — and `plays/base.yml`, the only play carrying the `common` role, is pinned to `hosts: drbu-cs-lab-pc1`, so `--limit` cannot widen it. That pinning needs sorting before this can be rolled out through the normal path.

`drbu-sw-cslab-w-pc3.cttb` remains powered off and unwakeable: it was shut down *before* this fix, so its NIC was still at `d`. It needs one physical power-on, after which the fix applies to it like any other host.
