# Plan — `utils/create-sudhanix-s0-installer.py` + stage0 USB on disk8

**Session goal:** build the Python tool, then use it to write a stage0 autoinstall USB
on `disk8`, for a host that will live **outside** the CTTB network.

**Decisions locked (PROMPTER, 2026-08-06):**

| Question | Answer |
|---|---|
| Install target | Stage-1 parity — minimal Ubuntu Server + `openssh-server` + `python3` + keys |
| Networking | Wired DHCP only (`match: en*`, dhcp4) |
| Apt mirror | Public archive, explicit: `archive.ubuntu.com` + `security.ubuntu.com`, `geoip: false` |
| Identity | Same as campus: `administrator`, campus password hash, both authorized keys |

**ARCHITECT calls (not escalated):**

- `--hostname` is **required**. Campus seeds use `hostname: computer` because stage 2
  renames the box; no campus Ansible run reaches this host, so the name must be right
  at install time.
- Writes are **dry-run until `--risks-confirmed`**, matching `utils/ldap`. The failure
  mode of this tool is `dd` over the wrong disk; the repo already has a convention for
  exactly that class of risk.
- ISO cache and output live in `build/autoinstall-usb/` — already gitignored (`*.iso`,
  `work/`), so no new ignore rules and no 3 GB artifacts near a commit.
- `build/autoinstall-usb/build-usb.sh` is **left alone**. Retiring it is adjacent, not
  required; noted as a follow-up.

---

## Interface

```
utils/create-sudhanix-s0-installer.py --hostname HOST --disk DEVICE [options]

Required:
  --hostname HOST         identity.hostname baked into the seed
  --disk DEVICE           /dev/diskN, or /Volumes/NAME (resolved via diskutil)

Safety:
  --risks-confirmed       perform the destructive write (default: dry-run plan only)
  --force-nonremovable    allow a target that is not external/removable

Source:
  --iso PATH              use a local ISO; skips download
  --iso-url URL           override the download source
  --refresh-iso           re-download even if the cache is warm

Seed:
  --apt-mirror URI        default http://archive.ubuntu.com/ubuntu/
  --apt-security URI      default http://security.ubuntu.com/ubuntu/
  --username NAME         default from netinstall-2404 defaults (administrator)
  --password-hash HASH    default from netinstall-2404 defaults
  --authorized-key KEY    repeatable; replaces the default key set when given
  --timezone / --locale / --keyboard
  --no-cttb-banner        omit the stage-1 /etc/issue banner

Output:
  --output-iso PATH       default build/autoinstall-usb/sudhanix-s0-<hostname>.iso
  --keep-work             retain the extraction tree for inspection
```

Defaults are read from `roles/netinstall-2404/defaults/main.yml` via PyYAML, so the
admin password hash and SSH public keys have **one** source of truth. CLI flags override.

---

## Stages

1. **Resolve config** — load role defaults, apply CLI overrides, build a frozen config
   object. Validate up front (hostname is a valid DNS label, password hash non-empty,
   at least one authorized key).
2. **Resolve target disk** — `/Volumes/X` → device node via `diskutil info`. Refuse the
   boot disk outright; refuse non-external/non-removable unless `--force-nonremovable`.
3. **Acquire ISO** — `--iso` > cache > `http://pxe.cttb/netinstall/ubuntu-live-server-noble-amd64.iso`
   (LAN) > `https://releases.ubuntu.com/24.04/` latest. Verify the ISO9660 `CD001`
   magic at offset `0x8001` before trusting the file.
4. **Render seed** — emit `user-data` (off-network autoinstall) + empty `meta-data`;
   keep a copy next to the output ISO for audit.
5. **Remaster** — `xorriso -osirrox` extract → patch `boot/grub/grub.cfg` (menu title
   plus `autoinstall ds=nocloud\;s=/cdrom/nocloud/` on every `/casper/vmlinuz` line) →
   copy in `nocloud/` → `xorriso -as mkisofs` repack.
6. **Write** — unmount, `sudo dd bs=4m`, `sync`, then read back and compare.

### The load-bearing fix

`build-usb.sh` hardcodes `--interval:local_fs:6264708d-6274851d::"$ISO_FILE"` for the
appended EFI partition. Those are 512-byte LBAs of GPT partition 2 **on the 24.04.2 ISO
specifically**. Point it at 24.04.3 or 24.04.4 and the repack silently produces a stick
that boots on BIOS and fails on UEFI — the worst kind of failure, because it looks like
it worked.

The Python tool derives them: parse the GPT header at LBA 1, walk the partition entry
array, find the entry whose type GUID is the ESP (`C12A7328-F81F-11D2-BA4B-00A0C93EC93B`),
and emit its `first_lba`/`last_lba`. Pure `struct` parsing, no output scraping, works on
any Ubuntu hybrid ISO.

---

## Acceptance criteria (validators)

Each is a command that passes or fails — no judgment reads.

1. `--help` exits 0; omitting `--hostname` or `--disk` exits non-zero with usage.
2. Dry-run against `/dev/disk8` prints a plan and mutates nothing — `diskutil list disk8`
   still reports the `UBUNTU 22_0` FAT32 volume afterward.
3. Rendered `user-data` parses as YAML; `autoinstall.version == 1`;
   `identity.hostname` equals the requested name; the serialized seed contains
   `archive.ubuntu.com` and **zero** occurrences of `cttb` in any apt URI.
4. GPT parser, run against the real ISO, finds exactly one ESP with a plausible extent
   (start > 0, size between 1 and 16 MB).
5. Remastered ISO: `xorriso -indev out.iso -find /nocloud` lists `user-data` and
   `meta-data`; the extracted `boot/grub/grub.cfg` contains `autoinstall` and
   `ds=nocloud;s=/cdrom/nocloud/`.
6. Post-write: sha256 of the first 64 MB read back from `disk8` equals sha256 of the
   first 64 MB of the output ISO, and `diskutil list disk8` shows the Ubuntu ISO layout.

Validators 1–5 run without touching the USB. Only 6 requires the destructive write.

---

## Risks

- **~10 GB transient disk** (3.3 GB download + extract + repack). 106 GB free — fine.
- **`sudo dd`** prompts for the workstation password interactively.
- **disk8 is erased.** It currently holds a stale `UBUNTU 22_0` installer; confirmed as
  the intended target, but the dry-run gate means the erase never happens implicitly.
- **UEFI vs Secure Boot.** Per memory, DVGS Dells must not chain through `shimx64.efi`
  and want Secure Boot off. The remastered stick keeps the stock ISO's EFI loaders, so
  it behaves like stock Ubuntu media; if the destination host has Secure Boot on and
  refuses, that is the first thing to check.
