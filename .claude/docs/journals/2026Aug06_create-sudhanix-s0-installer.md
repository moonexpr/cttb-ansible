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
- **Open threads:**
  - `build/autoinstall-usb/build-usb.sh` is now superseded and carries a dead ISO URL
    plus the hardcoded ESP offsets. Deliberately left alone as out of scope; worth a
    GitHub issue to retire or redirect it before someone reaches for it.
  - The stick is unproven on real hardware — everything verified here is image-level.
    First boot on the target is the remaining validator.
  - Secure Boot must be off on the target, per the DVGS shim caveat in memory.
  - `.claude/docs/` and `.claude/plans/` are untracked and were deliberately not
    committed, per the no-Claude-artifacts-in-git rule.
