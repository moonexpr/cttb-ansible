End-to-end verified, and this can close once the fix in #118 is deployed beyond the one test host.

`drbu-sw-cslab-w-pc2.cttb` was powered off with `systemctl poweroff`, then woken by:

```
utils/pb util-wakeonlan --limit drbu-sw-cslab-w-pc2.cttb
```

run from a macOS controller that reaches campus over the Tailscale subnet router — the exact configuration that previously produced `changed=2, failed=0` while putting zero packets on the campus wire. The host came back in ~45 s.

So the delivery path described here is closed: controller → srv-vm (on-campus sender, driven via `raw` because it is Python 3.5) → magic packet on the target's L2 segment → wake.

One caveat learned during the test: the NIC is not armed the moment the host leaves the network. A packet sent immediately after poweroff was missed; the retry a couple of minutes later worked. A single failed wake right after a shutdown is not evidence of a delivery problem.
