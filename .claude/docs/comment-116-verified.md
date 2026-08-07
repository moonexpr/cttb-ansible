Fixed and verified, with two corrections to the original report.

**Correction 1 — the sender cannot run Ansible modules.** The obvious fix (`delegate_to: srv-vm` with `community.general.wakeonlan`) fails:

```
fatal: [... -> cttb-wol-sender]: FAILED! =>
  File "<stdin>", line 235
    print(f'FATAL: Unknown debug command {command!r}.  Doing nothing.')
SyntaxError: invalid syntax
```

srv-vm is Ubuntu 16.04 with Python 3.5.2, and the modern Ansible module wrapper uses f-strings (3.6+). Most of the campus core is in the same state — srv-nas, jumpbox, mon and ldap all report Python 3.5.2. The play now uses `raw`, which needs no Python module layer, with an inline snippet that avoids f-strings and byte escapes so it runs on 2.7 through 3.x.

**Correction 2 — I briefly concluded srv-vm's `lxdbr0` was a separate broadcast domain. That was wrong**, and worth recording so nobody re-derives it. The test that suggested it was confounded: the target had by then become unwakeable for an unrelated reason (#118), so *every* sender looked broken. Sniffing the lab segment directly settles it — srv-vm's broadcasts do arrive.

**Verification.** `tcpdump` on `eno1` of `drbu-sw-cslab-w-pc2.cttb` (10.11.16.14, same broadcast domain as the target), while running the fixed play from a macOS controller reaching campus over Tailscale:

```
18:34:20.238800 IP 10.11.1.3.51541 > 255.255.255.255.7: UDP, length 102
18:34:20.238977 IP 10.11.1.3.51541 > 255.255.255.255.9: UDP, length 102
18:34:20.239058 IP 10.11.1.3.51541 > 10.11.255.255.7:   UDP, length 102
18:34:20.239271 IP 10.11.1.3.51541 > 10.11.255.255.9:   UDP, length 102
4 packets captured
```

Before the fix, the same capture during the same play showed `0 packets captured`. The delivery path described in this issue is closed.

**What this does not fix.** The acceptance criterion "running the play from an off-campus controller wakes the target" cannot be met yet, and not because of anything in this play. The lab NICs ship with `Wake-on: d` and no persistence, so a cleanly shut-down host ignores the packets that now demonstrably reach it. Filed as **#118**, which is the harder half. Both had to be true for wake-on-LAN to look broken, and this fix alone would not have woken a single cleanly-shut-down machine.

Leaving this open until a host with an armed NIC is available to confirm an actual wake end-to-end.
