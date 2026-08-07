---
date: 2026-08-06
goal: "Create a new utils/create-sudhanix-s0-installer.py and then create a new stage0 usb-driven installer on disk8. Note that this image will be installed on a host outside of cttb's network."
session: goal
---

# Session Journal — 2026 Aug 06

## Open
- **Goal:** Create `utils/create-sudhanix-s0-installer.py`, then build a stage0 USB installer on `disk8`, for a host **outside** the CTTB network.
- **Started:** 17:42

## Log

### Spec phase — reconnaissance (17:42–17:55)

Prior art found: `build/autoinstall-usb/build-usb.sh` (bash, added 2026-05 for the
dvgs-lab3 24.04 reinstall) plus a static `build/autoinstall-usb/user-data`. It
downloads the live-server ISO, injects a nocloud seed, edits `boot/grub/grub.cfg`,
repacks with `xorriso -as mkisofs`, and `dd`s to a USB.

Facts established:

- **Its ISO source is dead.** `http://pxe.cttb/ansible_assets/isos/ubuntu-24.04.2-live-server-amd64.iso`
  → **404** (casualty of the 2026-05-12 pxe re-IP/cutover). Any new tool must not
  depend on that path.
- Live ISO sources that *do* work: `http://pxe.cttb/netinstall/ubuntu-live-server-noble-amd64.iso`
  (LAN, full) and `https://releases.ubuntu.com/24.04/` (24.04.3 = 3.30 GB, and 24.04.4;
  24.04.2 has been withdrawn).
- The slim ISO (`ubuntu-live-server-noble-amd64-slim.iso`, ~1.5 GB) is casper-only and
  *requires* an online apt for the install to complete — a poor fit for an off-network
  host unless its mirror is reachable.
- Build host toolchain OK: `xorriso` at `/opt/homebrew/bin/xorriso`, Python 3.14.6,
  PyYAML 6.0.3, 106 GB free.
- Workstation currently reaches **both** `pxe.cttb` (200) and the public internet, so
  the build can pull from either.
- `disk8` = external physical, 30.8 GB, single `DOS_FAT_32` partition labeled
  `UBUNTU 22_0` — a stale Ubuntu 22 installer stick, the intended target.

**Off-network consequences** (the crux of this goal). The campus autoinstall templates
are CTTB-bound in three places, all of which break outside the network:

1. `apt.mirror-selection` points at `http://apt.cttb/mirrors/ubuntu/` with `geoip: false`
   — unreachable, so the install stalls/fails at the mirror step.
2. The seed itself is fetched over HTTP from `pxe.cttb` in the PXE path — moot for USB
   (the seed rides on the stick at `/cdrom/nocloud/`), but the ISO fetch at *build* time
   must not assume it.
3. The stage-1 `/etc/issue` banner advertises a "Stage 2 installation" that no campus
   Ansible run can reach from outside.

Also noted for the rewrite: `build-usb.sh` hardcodes byte intervals
(`6264708d-6274851d`) for the appended EFI partition in its `xorriso` repack. Those are
specific to the 24.04.2 ISO and will silently produce an unbootable UEFI stick on any
other ISO. The Python tool should derive them from the ISO instead.

### Dev phase — tool build (18:00–18:35)

`utils/create-sudhanix-s0-installer.py` written and committed (`0898a797`), with
acceptance checks in `utils/tests/test-create-sudhanix-s0-installer.py`.

**The GPT fix paid off immediately.** On the 24.04.4 ISO the EFI System Partition
lives at LBA `6640484–6650643`. `build-usb.sh` hardcodes `6264708d-6274851d` (the
24.04.2 extent). Had we reused that script against a current ISO, the repack would
have produced a stick that boots fine under BIOS and fails under UEFI — a failure
that looks like success until the target machine refuses to boot. The tool now
parses the extent out of the ISO's GPT, so it tracks any Ubuntu hybrid image.
The test asserts the derived value differs from the old hardcoded pair.

ISO provenance: pulled `ubuntu-24.04.4-live-server-amd64.iso` (3,405,469,696 bytes)
from releases.ubuntu.com; sha256 verified against Ubuntu's published `SHA256SUMS`
(`e907d92e…138433`). Chose upstream over the LAN copy on pxe.cttb deliberately —
the campus ISO is unversioned and its provenance is a mirror, and this machine is
leaving the perimeter.

### Judgment calls made without escalating

- **`--hostname` is required**, not defaulted to `computer`. Campus seeds rely on
  stage-2 Ansible to rename the box; nothing renames this one.
- **Dry-run until `--risks-confirmed`**, matching `utils/ldap`. The plan output now
  enumerates the volumes about to be erased (`disk8s1: UBUNTU 22_0`) so the operator
  sees which stick they are destroying.
- **Raw device for the write** (`/dev/rdisk8` rather than `/dev/disk8`) — buffered
  writes to the plain node are roughly an order of magnitude slower on macOS.
- **Volume ID preserved** from the source ISO rather than overwritten with a custom
  label as `build-usb.sh` did. Less surface for casper to trip over.

### Hostname / mDNS (escalated — good thing it was)

PROMPTER supplied `sc-cslab-pc-right.local`. Two problems worth surfacing rather than
silently "fixing":

1. On Linux the `.local` suffix belongs to mDNS, not `/etc/hostname`.
2. **Ubuntu Server does not install `avahi-daemon`**, so a strict stage-1 base would
   not answer to `.local` at all — and off-campus, with no DNS the operator controls,
   mDNS is realistically the only way to find the host.

Resolved: `/etc/hostname` = `sc-cslab-pc-right`, plus `avahi-daemon` in the seed.
This drove a real interface addition — `--package` (repeatable), so the package list
is extensible instead of hardcoded. Had I quietly stripped the `.local` and shipped
stage-1 parity, the box would have arrived unreachable by the name it was given.

### Build + write (18:40–19:05)

First live run **failed** four minutes in, at the write step:
`dd: invalid number: '4m'`. Cause: Homebrew coreutils is on PATH at
`/opt/homebrew/opt/coreutils/libexec/gnubin`, so `dd` — under `sudo` too — is GNU
dd, which rejects the BSD lowercase size suffix. disk8 was untouched; the failure
landed after the repack but before any write. Fixed by passing plain byte counts,
which both implementations accept, in the write *and* the readback path. `V6` in
the test script now greps the source for a suffixed `bs=` so the class can't return.

The same shadowing bit a second time during verification: `stat -f%z` is BSD syntax,
GNU `stat` reads `-f` as "filesystem status", so `ISO_BYTES` came back empty, the
byte-compare hashed zero bytes on both sides, and printed a confident `MATCH`. The
sha256 was `e3b0c442…` — the hash of empty input — which is the tell. Redone with
`wc -c`. **Lesson: a comparison that can pass vacuously is not a validator.** Both
sides being equal means nothing if both sides are empty; the check needs a floor on
the input size, which it now has.

Second run succeeded. Verified:

- `diskutil list disk8` → GPT, 3.4 GB ISO partition + 5.2 MB ESP + 307 KB partition.
- Seed inside the image: `hostname: sc-cslab-pc-right`, `administrator`,
  `openssh-server` / `python3` / `avahi-daemon`, apt on archive+security.ubuntu.com.
- `boot/grub/grub.cfg`: `set timeout=5`, entry renamed to
  `Autoinstall Sudhanix stage 0 (sc-cslab-pc-right)`, boot line
  `linux /casper/vmlinuz autoinstall ds=nocloud\;s=/cdrom/nocloud/ ---`.
- Stick vs. ISO: 3246 MiB byte-identical (sha256 `7dbacca9…`).
- Ejected at PROMPTER request.

Note: only the primary menu entry is patched. The HWE entry is left stock, so
manually selecting it boots a live session rather than autoinstalling. With
`timeout=5` and the autoinstall entry first, the unattended path is the default.

### Incident — subiquity crash on first boot (18:33–19:15)

The stick booted and the grub patch worked exactly as built: `/proc/cmdline` on the
target read `BOOT_IMAGE=/casper/vmlinuz autoinstall ds=nocloud;s=/cdrom/nocloud/`.
The installer then crashed. Apport report in `/var/crash/`:

```
ValueError: Unrecognized time zone request "US/Pacific"
  subiquity/server/controllers/timezone.py:109
```

**Root cause.** `generate_possible_tzs()` builds the accepted set as
`["", "geoip"] + timedatectl list-timezones`, which lists canonical zones only.
`US/Pacific` is a tzdata *backward-compat alias*: absent from that list, and
`/usr/share/zoneinfo/US/Pacific` is not even shipped in the installer image.
Verified on the box: `America/Los_Angeles` → 1 match, `US/Pacific` → 0.

The value came from `ni_timezone` in `roles/netinstall-2404/defaults/main.yml`, which
also feeds all three campus autoinstall templates — so this was never specific to the
off-campus build. **The deployed seeds on pxe.cttb still serve `timezone: US/Pacific`
for desktop-minimal, desktop, and server.** The default is fixed in git; a
`deploy-netinstall-2404` run is still owed to push it.

**Recovery, without rewriting the USB.** The request was to scp the rebuilt ISO to the
target and `dd` it onto the stick from there. That would have bricked the machine:
`/dev/sdc1` is mounted at `/cdrom`, and `/cdrom/casper/*.squashfs` are the lowerdirs of
the `/cow` overlay that *is* `/`. Overwriting the stick while booted from it pulls the
running rootfs out mid-write — a half-written stick and a dead machine, with no way to
retry remotely. Since `/autoinstall.yaml` lives on the writable overlay, patching it and
restarting `snap.subiquity.subiquity-server.service` fixed the run with no USB write at
all. Worth remembering as the general recovery path for a crashed unattended install.

**Two more things the box taught us, both caught before damage:**

1. `storage.layout` defaults to `match = {"size": "largest"}`. This machine has a 931 GB
   HDD and a 238 GB SSD, *both* holding BitLocker-encrypted Windows volumes. Left alone,
   the installer would have wiped the **HDD**, not the SSD the operator wanted. Disk
   choice was escalated and pinned explicitly.
2. The first pin used the serial from `lsblk` (`S3U0NE0K770518`) and failed with
   `Failed to find matching device`. Subiquity matches `ID_SERIAL` via `fnmatch`, not
   `ID_SERIAL_SHORT` — the correct string was
   `SAMSUNG_SSD_PM871b_M.2_2280_256GB_S3U0NE0K770518`. It failed safely, before touching
   any disk.

Install then proceeded to `sdb`: `sdb1` 1 GB vfat → `/target/boot/efi`, `sdb2` 237.4 GB
ext4 → `/target`. `sda` left untouched.

### Offsite stage 2 (19:30–22:20)

Stage 2 could not run against `sc-cslab-pc-right` as written. Verified from the
host: `apt.cttb`, `storehouse.cttb`, `wiki.cttb`, `ldap.cttb` all fail to resolve
and `10.11.1.1` is unreachable, while the public internet works. `roles/common`
would have rewritten the box's apt config to `http://apt.cttb/mirrors/ubuntu/`
and every later `apt:` task would have failed.

**The coupling turned out to be variable-driven, not hardcoded** — which is what
made this tractable. `deb_mirror`, `ansible_assets_url`, `chrome_repo`,
`ntp_servers` are all Jinja-derived from `group_vars/all`, and `cups_srv`,
`nfs_homes_host`, `global_proxy` are already guarded by `is defined`. So the fix
rebinds variables (`group_vars/offsite`) rather than forking the role tree. The
entire apt fix is **one variable**: `deb_mirror: http://archive.ubuntu.com`, since
`ubuntu.sources.j2` renders `{{deb_mirror}}/ubuntu/` and archive.ubuntu.com
carries all four noble suites with all four components.

Two roles could not be rebound and were handled structurally:

- **`ldap-client` excluded from the play**, not tag-skipped: it asserts
  `'ldap_clients' in group_names` with no seam, `access.conf.j2` needs an
  `ldap_group_acl_string` that has no default, and enabling LDAP nsswitch against
  an unreachable directory would hang `getent` and login.
- **`sudhanix-vajra-tool` gained a seam.** It installs vajra from apt.cttb with no
  override — but the `.deb` is already vendored in the role's `files/`. Added
  `vajra_install_from_local_deb` (default false, campus byte-identical) so offsite
  installs the committed .deb instead. vajra didn't have to be sacrificed.

**Assets.** `sudhanix-core` fetches ~420 MB of themes, fonts, wallpapers and
browser tarballs from storehouse.cttb, and most of those `unarchive` tasks have
**no rescue** — a miss aborts the play mid-run. This Mac reaches storehouse over
Tailscale; the target does not. `utils/offsite-relay` mirrors them locally and
serves them to the target. **Default transport is an SSH reverse tunnel**, because
the two machines are on different routed subnets (192.168.40.19/23 vs
192.168.1.244/24) and inbound would depend on the gateway plus the macOS
firewall; the tunnel rides the SSH connection we already have. `check` proved it
works before committing to a 20-minute run.

### Judgment calls this phase

- **Separate `inventory/offsite.ini`, not a group in the campus inventory.**
  `sudhanix26-rollout-stage2.yml` is `hosts: all`, so one forgotten `-l` would
  point a campus lab PC at a mirror it cannot reach. Separate files make that
  class of error unrepresentable rather than merely discouraged.
- **Vaulted become password copied verbatim, not inherited.** Making `offsite` a
  child of `cttb_hosts` would be DRY-er, but that group is the campus umbrella —
  any campus var added there later would leak silently onto every offsite host.
- **Ran from a clean worktree at HEAD.** Uncommitted wake-on-lan work by another
  session sat in `roles/common/tasks/setup/default.yml`, which this play executes.
  Mid-edit netplan code going to a machine with no console is a truck roll, so the
  run used committed code only and left the working tree untouched.

### `--check` is not a rehearsal for this play

The dry run failed at `cttb-ca-client : create cttb-cacert.pem symlink` —
`/etc/ssl/certs/CTTB-Root-CA.pem` does not exist. **Not a defect.** `shell:` tasks
are skipped under `--check`, so `update-ca-certificates -f` never runs and never
generates the .pem, but `file: state=link` *does* execute and validates its source.
The campus play fails identically under `--check`. Worth knowing before someone
reads that failure as an offsite-specific bug.

### Offsite stage-2 result — clean

`ok=292 changed=194 unreachable=0 failed=0 skipped=186 rescued=0`. A zero
`rescued` count matters here: it means no asset fetch fell into a rescue block, so
nothing degraded silently.

Verified on the target afterwards:

| Check | Result |
|---|---|
| apt config references `.cttb` | none; `URIs: http://archive.ubuntu.com/ubuntu/` |
| WhiteSur GTK + icon themes, cursors | present |
| Inter Display font | `/usr/share/fonts/truetype/inter-display`, 18 `fc-list` matches |
| bigsur sound theme, CTTB wallpapers | present |
| Firefox / Thunderbird | `/opt/firefox`, `/opt/thunderbird` |
| vajra | `vajra 1.0.0 (stable)` — **from the vendored .deb, no apt.cttb** |
| LDAP client packages | 0 installed, as intended |
| NTP | `0/1/2.pool.ntp.org` |

**The netplan handover was verified rather than assumed.** `nmcli` reports `eno1`
as `unmanaged`, which looks alarming but is correct — networkd still owns the link
until reboot. The decisive artifact is the keyfile `netplan generate` produces:

```ini
[match] interface-name=en*;
[ipv4] method=auto
[ethernet] wake-on-lan=1
```

NetworkManager will claim `en*` with DHCP at next boot, so the machine comes back.
Wake-on-LAN is armed as a side effect of the committed `99-wake-on-lan.yaml`
drop-in deep-merging into cloud-init's `id0` stanza — the exact case that
drop-in's comment says it requires.

**Minor defect found, not fixed (fleet-wide, out of scope):**
`/etc/netplan/01-network-manager-all.yaml` lands mode `0644` while the other
netplan files are `0600`, and `netplan generate` warns "Permissions ... are too
open". The `copy` task in `roles/sudhanix-core/tasks/lookandfeel.yml` sets no
`mode`. Affects every Sudhanix host, not just offsite.

### The reboot earned its keep (2026-08-07, 02:19)

Rebooting `sc-cslab-pc-right` was optional — the generated keyfile already showed
`[ipv4] method=auto`, so the handover was "verified". Doing it anyway surfaced two
things the static check could not.

**The host came back at a different address.** `.244` went silent; the machine was
alive at **`.252`**. NetworkManager sends a different DHCP client identifier than
networkd, so the reboot produced a new lease. mDNS found it immediately —
`avahi-daemon`, added to the stage-0 seed precisely because an off-campus box has
no DNS we control, is the only reason the machine was not simply "lost".
`inventory/offsite.ini` now addresses it by `sc-cslab-pc-right.local` instead of a
pinned IP, which is strictly more durable.

**A fleet-wide defect in the wake-on-LAN work.** The NIC came back as `eth0`, not
`eno1`. udev attributes it exactly:

```
ID_NET_LINK_FILE=/etc/systemd/network/10-wake-on-lan.link
ID_NET_NAME=eth0
ID_NET_NAME_ONBOARD=eno1
```

`roles/common`'s `10-wake-on-lan.link` matches `Type=ether` and sets **no
`NamePolicy=`**. systemd applies exactly one `.link` per device — first match in
lexical order — so a file at `10-` outranks the stock `99-default.link`, and with
no NamePolicy the device keeps its *kernel* name. Predictable interface naming was
silently switched off on every host that received the file.

Not cosmetic: netplan writes its NM profile with `[match] interface-name=en*`,
which a renamed `eth0` no longer satisfies, so `netplan-id0` went **inactive** and
NM's fallback wired profile took the link. This host is on DHCP, so it recovered
invisibly. A host with static or interface-keyed netplan config would have come up
misconfigured — and on campus that is a walk down the hall, but the same code path
ships everywhere.

Fixed by copying `NamePolicy`/`AlternativeNamesPolicy` verbatim from
`99-default.link`, so naming is stock and `WakeOnLan=magic` still applies.
Wake-on-LAN itself was never broken — `ethtool` reports `Wake-on: g`. **Hosts that
already have the old file keep renaming until they receive the corrected one**, so
it wants deploying before the next round of reboots.

The general lesson: a config check that reads the *intended* state cannot see a
device that has been renamed out from under the match clause. Only the reboot could.

### Pre-push scan found a live credential leak (2026-08-07)

Checking what a `git push` would publish — this repo is **public** — surfaced
something unrelated to the session's goal and more serious than anything in it.

`utils/sysadmintk/ldap_lib.py` built its bind arguments as
`["-x", "-D", bind_dn, "-w", bind_pw]` and ran every command with
`subprocess.run(..., check=True)`. A non-zero exit therefore raised
`CalledProcessError`, whose `__str__` renders the **entire argv**. One failed
LDAP call printed the bind password into any traceback, log line or error report
that carried the exception; `reset_password` additionally carried the user's new
password as `-s <password>`.

Worse, `.claude/docs/ldap-lib-credential-leak-issue.md` — a precise, working
description of how to trigger it — had **already been pushed to the public
remote** (in `8da7a667`, a batch that committed 28 issue/comment drafts at once).
So the exploit description and the unfixed code were public simultaneously. Every
acceptance box in that document was still unchecked.

**Fixed.** `subprocess.run` is now confined to a single `_run()` helper that
checks the return code itself and raises `LdapCommandError` carrying the tool
name, return code and stderr — never the argv. The ldap tools print their
diagnostics to stderr without the secret, so nothing diagnostic was lost:

```
before: CalledProcessError: Command '['ldapsearch', ..., '-w', '<pw>', ...]'
after:  ldapsearch failed (exit 249): ldap_search_ext: Bad search filter (-7)
```

Verified against the live directory: `utils/ldap group it` still resolves
members, and a deliberately malformed filter produces the clean message above.
`utils/tests/test-ldap-lib-redaction.py` asserts the bind password, new password
and bind DN are absent from the exception, that stderr and returncode survive,
and — via AST, so a docstring naming the hazard cannot satisfy it — that no call
site reintroduces `check=True`.

The `idstore_*` modules keep `check=True` deliberately: their argv carries only a
service name, with the secret returned on stdout.

**The drafts are untracked now, but that is not containment.** They were already
pushed; they remain in history and in any clone or fork. `.claude/docs/*` is
gitignored with `!.claude/docs/journals/`, so journals still ship and the drafts
cannot be swept in again. Whether to rotate the LDAP bind credential is the
operator's call and is not resolved here.

**The broader lesson.** Retiring the no-Claude-artifacts rule was right for
journals, which are written to be read. `.claude/docs/` also held issue drafts
staged for `gh issue create` — scratch, not documentation — and a blanket
`git add .claude/docs/` could not tell the difference. The gitignore now draws
that line explicitly rather than relying on whoever runs the next `git add`.

### Wake-on-LAN .link fix deployed — partial by necessity

`utils/pb sudhanix26-rollout-stage2 -l cttb_hosts -t wake_on_lan`, 39 hosts
attempted:

| Outcome | Count | Detail |
|---|---|---|
| Fixed | 3 | `dvgs-lab2`, `dvgs-lab3`, `dvgs-lab8` |
| Unreachable | 32 | lab PCs powered off — expected at this hour |
| Failed | 4 | `dvbs-lab12/13`, `dvbs-lib1/2` |

The four failures are **pre-existing and unrelated**: they run Ubuntu 20.04 with
Python 3.8.10, and this workstation's ansible-core requires ≥3.9 on the target, so
they die at Gathering Facts before any task. (`plays/util-upgrade-to-py3.9.yml`
sits untracked in the tree, so this is already known work.)

**The fix arrived in time for all three reachable hosts.** Each now carries the
`NamePolicy` lines, and each still has a predictable interface name — `enp2s0`,
`eno1`, `enp2s0` — not `eth0`. They had not rebooted since receiving the bad
`.link`, so they will never rename.

Verifying also confirmed the drop-in gate is correct. `dvgs-lab2`/`lab8` have no
`50-cloud-init.yaml`, so no netplan ethernet stanza; the drop-in is correctly
withheld and they are armed via the udev path (`Wake-on: g`). `dvgs-lab3` has the
cloud-init stanza, received the drop-in, and its NM keyfile reads
`wake-on-lan=1`; `ethtool` still reports `d` only because a keyfile change applies
on connection reactivation, so it arms at next boot.

**Residual risk:** the 32 powered-off hosts may still hold the old `.link` and
will rename at their next boot unless they receive stage 2 first. Re-run the same
tag-scoped command when the labs are up.

## Close
- **Summary:** Built `utils/create-sudhanix-s0-installer.py` (plus acceptance checks
  in `utils/tests/`) and used it to write a verified stage-0 autoinstall USB on disk8
  for `sc-cslab-pc-right`, an off-campus host. Two commits: `0898a797`, `e0aefa0f`.
- **Judgment calls:** Required `--hostname` rather than defaulting to `computer`;
  dry-run until `--risks-confirmed`; derived the ESP extent from the ISO's GPT instead
  of inheriting `build-usb.sh`'s hardcoded 24.04.2 offsets (which would have silently
  broken UEFI boot on 24.04.4); preserved the source volume ID; wrote via `/dev/rdisk8`.
  Escalated the `.local` hostname question rather than silently stripping it — that
  surfaced the avahi gap and drove the `--package` flag.
- **Closed during the session:** pxe.cttb seeds deployed (`desktop-minimal` and
  `server` now serve `America/Los_Angeles`; the live grub.cfg offers only those
  two, so every bootable path is fixed); netplan perms tightened to 0600;
  `--with-assets` built and covered by V8; the offsite host rebooted and verified.
- **Open threads:**
  - **Deploy the `10-wake-on-lan.link` NamePolicy fix.** Any host still carrying
    the old file renames its NIC at next reboot. Benign on DHCP hosts, not
    necessarily on others. Highest-priority follow-up.
  - The stale `autoinstall/ubuntu/desktop/user-data` on pxe.cttb still reads
    `US/Pacific`. No menu references it and the play's loop does not render it, so
    it is inert — but it is a live trap if anyone wires up that profile.
  - `deploy-netinstall-2404` left one task failing: `fix postinst script
    permissions` timed out waiting for a sudo prompt on pxe. The seed sync itself
    completed; that task was never reached in anger.
  - `build/autoinstall-usb/build-usb.sh` is superseded — dead ISO URL and hardcoded
    ESP offsets. Worth retiring before someone reaches for it.
  - The next offsite stick should be built `--with-assets`, after which
    `offsite_asset_relay: /opt/sudhanix-assets` retires the relay for that host.
  - Secure Boot must be off on any target, per the DVGS shim caveat in memory.
  - The no-Claude-artifacts-in-git rule was **retired** mid-session; journals and
    plans now ship with the repo. Note the repo is PUBLIC — no credentials in these.
