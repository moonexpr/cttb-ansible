Rolled out to every reachable lab desktop via `utils/pb base -l cttb_hosts --tags wake_on_lan` (which needed #120 fixed first — the play could not target anything but one hardcoded host).

**The fix is now conditional**, because the fleet is not uniform:

| Host | netplan ethernet | before | action |
|---|---|---|---|
| `drbu-sw-cslab-w-pc2` | `id0` | `d` → `g` | reference fix, wakes from S5 |
| `dvgs-lab3` | `id0` | `d` | keyfile flipped `wake-on-lan=0` → `1`; arms at next boot |
| `dvgs-lab2` | none | **`g`** | `.link` only — netplan drop-in correctly skipped |
| `dvgs-lab8` | none | **`g`** | `.link` only — netplan drop-in correctly skipped |

Only hosts whose networking is *defined* in netplan were ever broken: netplan writes an explicit `wake-on-lan=0` into the keyfile it generates, and an explicit value beats the `conf.d` default. Hosts with no netplan ethernet stanza let NetworkManager make its own auto-connection, which never carries that explicit `0` — so the role's existing `ethernet.wake-on-lan = 64` already armed them. `dvgs-lab2` and `dvgs-lab8` sitting at `g` untouched, next to `dvgs-lab3` at `d`, is what established that.

This matters for safety, not just tidiness: writing the drop-in to a host with no `id0` stanza would have netplan read it as a standalone ethernet with no `dhcp4`, and the interface could come up unaddressed on next boot. The role now probes for the stanza and skips the drop-in where there is none.

Two other things the rollout surfaced, both fixed in the same commit:

- `/etc/systemd/network` does not exist on desktops that never used systemd-networkd, so the `.link` copy failed with "not writable" until the role creates it.
- `plays/base.yml` had no `become: true`. That went unnoticed for as long as it did because every file the role manages already existed and matched, so `copy` was a no-op needing no privileges. The first genuinely new file exposed it.

**Not covered by this rollout:**

- 51 hosts were powered off and will pick the change up on a later run.
- `dvbs-lab12`, `dvbs-lab13`, `dvbs-lib1`, `dvbs-lib2` fail before any task: `Ansible requires Python 3.9 or newer on the target. Current version: 3.8.10` — still Ubuntu 20.04, so unreachable by Ansible until they are upgraded.
- `drbu-sw-cslab-w-pc3` is still powered off and needs a physical power-on; it was shut down before the fix, with its NIC at `d`.
