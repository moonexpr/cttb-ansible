# Update Journal: Ubuntu 24.04 Upgrade

**Branch:** feature/ubuntu22-upgrade
**Started:** 2026-04-16
**Test machine:** dvgs-testmachine.cttb (formerly dvgs-lab3, IP: 10.11.9.23)

> **See also:** [DEPLOYMENT.md](DEPLOYMENT.md) — full deployment pipeline & commands | [BACKLOG.md](BACKLOG.md) — consolidated task list

---

## Pre-deployment State

| Field | Value |
|-------|-------|
| OS | Ubuntu 20.04.6 LTS (focal) |
| Kernel | 5.15.0-139-generic |
| Hostname | dvgs-lab3 |
| IP | 10.11.13.78 (wlo1, WiFi, DHCP) |
| Python | 3.13 (discovered by Ansible) |
| Inventory IP | 10.11.9.23 (stale — does not match actual) |

## Events

### 2026-04-16 — Session Start

1. **GRUB issue:** Machine wouldn't show GRUB menu (timeout=0). Had to catch GRUB CLI manually.
2. **Login issue:** Mac-layout Logitech keyboard caused credential entry problems. TTY was also locked out.
3. **Recovery:** Booted via GRUB CLI, set temporary credentials (`administrator:a`).
4. **SSH initially down:** Host was pingable but SSH timed out. Started `openssh-server` from console.
5. **Connectivity confirmed:** SSH and Ansible ping both working.

### Notes

- Host is on WiFi (`wlo1`) not wired Ethernet — inventory `ansible_address` is wrong for current network config.
- Python 3.13 present on a 20.04 system is unexpected; may have been manually added.
- Ansible warns about interpreter discovery — consider setting `ansible_python_interpreter` explicitly.

---

## Pre-deploy Snapshot

Captured to `/root/pre-deploy-snapshot-20260416-123912` on dvgs-lab3:

```
configs.tar.gz    — /etc/apt, /etc/cups, /etc/ldap, /etc/pam.d, /etc/fstab, /etc/lightdm, /etc/xdg, CA certs
dpkg-selections.txt — full package list (for dpkg --set-selections restore)
services.txt      — running services at snapshot time
ip-addr.txt       — network interface state
netplan.txt       — netplan config
```

Rollback: extract `configs.tar.gz` to `/`, restore packages via `dpkg --set-selections < dpkg-selections.txt && apt-get dselect-upgrade -y`, reboot.

---

## Issues Found and Fixed

### 1. Inventory group name mismatch (BLOCKER)

**Problem:** `plays/cs-lab-2404.yml` targets `dvgs_cs_lab` but inventory defined `dvgs_cslab` (no underscore between "cs" and "lab"). Same for `dvbs_cslab` and `drbu_cslab`. Ansible silently matched no hosts.

**Fix:** Renamed all three groups in `inventory/hosts_os_upgrade.ini`:
```
[dvgs_cslab]  → [dvgs_cs_lab]
[dvbs_cslab]  → [dvbs_cs_lab]
[drbu_cslab]  → [drbu_cs_lab]
```
Also updated `:vars` sections and `[*_hosts:children]` references.

**Command to verify:** `ansible-inventory --graph | grep cs_lab`

### 2. Duplicate host entries

**Problem:** dvgs-lab1 through dvgs-lab8 were listed twice in the `[dvgs_cs_lab]` group.

**Fix:** Removed the duplicate block (was lines 214-223).

### 3. Deprecated `include:` directive (BLOCKER)

**Problem:** `roles/desktop-20.04/tasks/main.yml` used bare `include:` which was removed in ansible-core post-2023. Ansible 2.20 rejects it outright.

**Fix:** Replaced all 6 occurrences with `include_tasks:`:
```yaml
# Before
- include: lubuntu.yml
# After
- include_tasks: lubuntu.yml
```

Files affected: `lubuntu.yml`, `lang.yml`, `lookandfeel.yml`, `sw.yml`, `sw-goldendict.yml`, `sound.yml`

### 4. group_vars not loaded for playbook runs (BLOCKER)

**Problem:** `group_vars/` at repo root was not found when running playbooks. Ansible resolves `group_vars/` relative to the **inventory file location** (`inventory/hosts_os_upgrade.ini`), so it looked for `inventory/group_vars/` which didn't exist.

Ad-hoc commands (`ansible -m debug`) worked because `ANSIBLE_HOSTS` env var (from `utils/setup-env`) points to `./hosts` at repo root, where `./group_vars/` IS adjacent.

**Fix:** Created symlinks:
```bash
ln -s ../group_vars inventory/group_vars
ln -s ../host_vars inventory/host_vars
```

**How to verify:** `ansible dvgs-lab3.cttb -m debug -a "var=deb_mirror"` should show the resolved value.

### 5. APT mirror unreachable (RESOLVED)

**Problem:** `apt.cttb` refused connections from dvgs-lab3 on WiFi.

**Fix:** Connected device to WAN port (new IP: 10.11.30.32). APT mirror reachable. Updated inventory with `ansible_host=10.11.30.32`.

### 6. Python 3.8 / Ansible 2.20 incompatibility (RESOLVED)

**Problem:** Ansible 2.20 requires Python 3.9+ on targets. Ubuntu 20.04 ships Python 3.8. The `apt` module produced deserialization errors (dual JSON output from 3.8 and 3.13 interpreters).

**Root cause:** `/usr/bin/python3` symlinked to `python3.8`. The `apt` module's bootstrap discovers `/usr/bin/python3` regardless of `ansible_python_interpreter` setting. Also, `python3-apt` bindings (`apt_pkg.so`, `apt_inst.so`) were compiled for cpython-38 only.

**Fixes applied on dvgs-lab3:**
```bash
# Repoint python3 to 3.13
sudo ln -sf python3.13 /usr/bin/python3

# Symlink apt bindings for 3.13
sudo ln -sf apt_pkg.cpython-38-x86_64-linux-gnu.so \
  /usr/lib/python3/dist-packages/apt_pkg.cpython-313-x86_64-linux-gnu.so
sudo ln -sf apt_inst.cpython-38-x86_64-linux-gnu.so \
  /usr/lib/python3/dist-packages/apt_inst.cpython-313-x86_64-linux-gnu.so
```

**Note:** These symlinks are fragile (3.8 ABI loaded by 3.13). This workaround is acceptable for testing but reinforces the decision to do clean PXE reinstalls rather than in-place upgrades.

### 7. Deprecated `warn` parameter in command module (RESOLVED)

**Problem:** `roles/common-20.04/tasks/main.yml` used `warn: false` in `command` module args. The `warn` parameter was removed in ansible-core 2.20+.

**Fix:** Removed `args: warn: false` from both `apt autoremove` tasks (lines 278-279, 294-295).

### 8. `ubuntu-desktop-minimal` package not available on 20.04

**Problem:** `roles/desktop-20.04/tasks/lubuntu.yml` references `ubuntu-desktop-minimal` which is a 22.04+ package.

**Resolution:** Not a bug — the `cs-lab-2404.yml` playbook is designed for post-PXE-install configuration on 24.04, not for running on 20.04 hosts. Decision made to use PXE reinstall path instead of in-place upgrade.

---

---

## Dry Run Results (cs-lab-2404.yml against 20.04 host)

| Metric | Value |
|--------|-------|
| Tasks passed | 31 |
| Tasks failed | 1 (ubuntu-desktop-minimal — expected, 24.04 package) |
| Tasks skipped | 16 |
| Changed | 1 (apt cache refresh) |

All infrastructure/config tasks pass. Package installation tasks expect 24.04. This confirms the playbook is ready for post-PXE-install use.

---

## Decision: PXE Reinstall over In-Place Upgrade

**Date:** 2026-04-16

In-place dist-upgrade (20.04 → 22.04 → 24.04) was considered but rejected:
- Requires two version hops (can't skip)
- `do-release-upgrade` is fragile over SSH, often needs interactive prompts
- Python 3.8 / Ansible 2.20 incompatibility makes automation unreliable on 20.04
- Leaves package cruft and broken configs

**Chosen path:** PXE reinstall to Ubuntu 24.04 via the `netinstall-2404` role, then configure with `cs-lab-2404.yml`.

### PXE Pipeline Assessment

The `netinstall-2404` role was reviewed. The pipeline is **fully autonomous** — no interactive gates:
- `autoinstall` + `noprompt` kernel params
- `PROMPT 0` in PXE menu (auto-boots, 10s timeout to local disk)
- Pre-set admin password hash, SSH key injection via late-commands
- Post-install script is non-interactive

### RISK: Storage layout is destructive

All autoinstall profiles use `storage: layout: name: direct` which **wipes the entire disk**. Lab machines (including dvgs-lab3) have Windows partitions (OS, WINRETOOLS, DELLSUPPORT, Image recovery) that will be destroyed.

**Decision:** Risk accepted. Lab machines are Ubuntu-primary; Windows partitions are legacy OEM installs not in active use. Dell recovery can be rebuilt from Dell media if ever needed.

---

## Autoinstall USB Build

**No PXE server SSH access**, so built a USB installer instead.

Built at `build/autoinstall-usb/`:
- Downloaded ISO from `http://pxe.cttb/ansible_assets/isos/ubuntu-24.04.2-live-server-amd64.iso`
- Injected `user-data` with desktop profile (lubuntu-desktop, administrator account, SSH keys, hostname dvgs-lab3)
- Repacked with xorriso preserving original boot parameters
- Output: `ubuntu-24.04.2-autoinstall-dvgs-lab3.iso` (3.0GB)
- GRUB: 5s timeout, autoinstall is default entry
- Written to 59GB Flash Disk at `/dev/rdisk4` via dd

### USB build commands (for reference)
```bash
cd build/autoinstall-usb

# Download ISO (skip if cached)
curl -L -o ubuntu-24.04.2-live-server-amd64.iso \
  http://pxe.cttb/ansible_assets/isos/ubuntu-24.04.2-live-server-amd64.iso

# Extract
xorriso -osirrox on -indev ubuntu-24.04.2-live-server-amd64.iso -extract / work/iso

# Inject autoinstall
cp user-data work/nocloud/user-data
cp meta-data work/nocloud/meta-data
cp -r work/nocloud work/iso/nocloud
# (also overwrote work/iso/boot/grub/grub.cfg with autoinstall entry)

# Repack (uses original ISO's boot params)
xorriso -as mkisofs \
  -r -V 'Ubuntu 24.04 Autoinstall' \
  -o ubuntu-24.04.2-autoinstall-dvgs-lab3.iso \
  --grub2-mbr --interval:local_fs:0s-15s:zero_mbrpt,zero_gpt:ubuntu-24.04.2-live-server-amd64.iso \
  --protective-msdos-label -partition_cyl_align off -partition_offset 16 \
  --mbr-force-bootable \
  -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b \
    --interval:local_fs:6264708d-6274851d::ubuntu-24.04.2-live-server-amd64.iso \
  -appended_part_as_gpt \
  -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
  -c '/boot.catalog' -b '/boot/grub/i386-pc/eltorito.img' \
  -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
  -eltorito-alt-boot -e '--interval:appended_partition_2:::' -no-emul-boot \
  work/iso

# Write to USB
sudo dd if=ubuntu-24.04.2-autoinstall-dvgs-lab3.iso of=/dev/rdisk4 bs=4m status=progress
diskutil eject /dev/disk4
```

---

## ~~CURRENT BLOCKER: USB not visible in Dell boot menu~~ (RESOLVED)

**Date:** 2026-04-16 | **Resolved:** 2026-04-21

USB drive written with `dd` but not appearing in F12 boot menu on dvgs-lab3 (Dell Inspiron 5400 AIO). Superseded — dvgs-lab3 was installed via SSH debootstrap (2026-04-21) after USB autoinstall had SQUASHFS corruption. USB path abandoned for this host.

**Troubleshooting checklist:**
- [x] Verify partition table on Mac: `diskutil list /dev/disk4`
- [x] Try different USB port on the Dell
- [x] Enter BIOS Setup (F2) and check:
  - [x] Secure Boot is **disabled**
  - [x] USB Boot is **enabled**
  - [x] Boot list mode includes **UEFI**
- [x] If partition table looks wrong, may need alternative write method — USB booted on 04-17, but had I/O corruption

---

## Role Refactor: desktop-22.04 & common-22.04

**Date:** 2026-04-16

Forked `desktop-20.04` → `desktop-22.04` and `common-20.04` → `common-22.04` for the 24.04 upgrade path. Applied Ansible 2.20 compatibility fixes and best-practice cleanup across both roles.

### Changes made
- `include:` → `include_tasks:` (all files)
- Removed deprecated `warn: false` from command module
- Replaced deprecated `apt_key` with signed-by keyring pattern (common, sw-browser)
- `with_items` → `loop` everywhere
- `state: latest` → `state: present` for stability
- Fixed broken Zoom/Skype register logic (`== 0` → `is not changed`)
- Replaced `shell: systemctl` with `systemd` module (sound.yml)
- Added `changed_when: false` to non-idempotent commands (im-config, locale)
- Added handlers for pulseaudio and lightdm
- Consistent tag strategy across all task files
- Removed legacy backup files (.0, .1.reordered, etc.)
- Resolved all TODO items (lightdm autologin, wps-fonts, autoremove)

### Software additions
- Visual Studio Code (via Microsoft repo, signed-by keyring)
- Blender, Inkscape, Kdenlive (creative tools for students)

### Theme: WhiteSur
Switched from Clearlooks/windos10-icons to WhiteSur (macOS Aqua-inspired). All theme references are now templatized via variables in `defaults/main.yml`.

**ACTION REQUIRED — Upload to asset server before deployment:**

Upload these tarballs to `ansible_assets_url` (same location as `windos10-icons-custom.tar.gz`):

| File | Source | Extract to |
|------|--------|------------|
| `WhiteSur-gtk-theme.tar.gz` | https://github.com/vinceliuice/WhiteSur-gtk-theme | `WhiteSur/` in `/usr/share/themes/` |
| `WhiteSur-icon-theme.tar.gz` | https://github.com/vinceliuice/WhiteSur-icon-theme | `WhiteSur/` in `/usr/share/icons/` |
| `WhiteSur-cursors.tar.gz` | https://github.com/vinceliuice/WhiteSur-cursors | `WhiteSur-cursors/` in `/usr/share/icons/` |

**How to build the tarballs:**
```bash
# GTK theme
git clone https://github.com/vinceliuice/WhiteSur-gtk-theme.git
cd WhiteSur-gtk-theme
./install.sh -d /tmp/whitesur-gtk
cd /tmp/whitesur-gtk && tar czf WhiteSur-gtk-theme.tar.gz WhiteSur/

# Icon theme
git clone https://github.com/vinceliuice/WhiteSur-icon-theme.git
cd WhiteSur-icon-theme
./install.sh -d /tmp/whitesur-icons
cd /tmp/whitesur-icons && tar czf WhiteSur-icon-theme.tar.gz WhiteSur/

# Cursors
git clone https://github.com/vinceliuice/WhiteSur-cursors.git
cd WhiteSur-cursors
./install.sh
cd /usr/share/icons && tar czf /tmp/WhiteSur-cursors.tar.gz WhiteSur-cursors/
```

Then copy to the asset server:
```bash
scp /tmp/WhiteSur-*.tar.gz pxe.cttb:/path/to/ansible_assets/
```

---

## 2026-04-17 — USB Autoinstall with DRBU Wifi

### Changes made

1. **Set DRBU as default wifi SSID** in `roles/netinstall-2404/defaults/main.yml` (`ni_wifi_ssid: "DRBU"`). DRBU is an open network (no password).

2. **Added wifi config to USB user-data** in `build/autoinstall-usb/user-data` — added `wifis` block matching `wl*` interfaces with DRBU SSID.

3. **Fixed `build-usb.sh` — three bugs:**
   - **hdiutil hang:** Replaced unreliable `hdiutil attach` ISO extraction with direct `xorriso -osirrox` extraction. macOS `hdiutil` frequently hangs on Linux hybrid ISOs.
   - **xorriso repack failure:** The `--grub2-mbr` flag referenced `boot_hybrid.img` which doesn't exist in the extracted ISO. Fixed to use `--interval:local_fs:0s-15s:...` to pull boot sectors directly from the source ISO (matching the working command from the previous session).
   - **sed GRUB injection failure:** The sed pattern expected single space before `---` but the ISO has double space (`vmlinuz  ---`). Fixed with `*` glob. Also renamed the first menu entry to "Autoinstall Ubuntu 24.04 Desktop (CTTB)".

### USB test on dvgs-lab3

- Built repacked ISO on Mac, wrote to 59GB Flash Disk via `dd`
- USB booted successfully on dvgs-lab3 (F12 boot menu)
- GRUB menu appeared with stock entries (autoinstall params were NOT injected due to the sed bug — discovered after boot)
- **cloud-init crashed** with `OSError: [Errno 5] Input/output error` — USB drive I/O failure during boot
- Tried second boot — same I/O error
- Root cause likely: xorriso repack corruption, slow/flaky USB drive, or USB port issue

### Stock ISO test

- SSH'd into dvgs-lab3 (still on old 20.04 install — autoinstall never ran, disk not wiped)
- Wrote stock (unmodified) ISO directly to USB from `pxe.cttb` mirror via `curl | dd`
- USB write was very slow (~15 MB/s) — completed after ~4 minutes
- Machine powered off remotely after write

### Status

- The USB currently has the **stock ISO** (no autoinstall config)
- The build script bugs are **fixed but untested** — need to rebuild and re-test
- PXE server access **granted** (see 2026-04-21 entry)

---

## 2026-04-21 — PXE Server Access & Deployment

**Access:** `ssh rui-desktop2` (jump host) → `jc@pxe.cttb` (ProxyJump)
**PXE server:** Ubuntu 16.04, IP 10.11.1.23, kernel 4.4.0-179
**SSH key:** `~/.ssh/rui-desktop2` (passphrase in vault)
**Sudo password:** stored in `inventory/group_vars/pxe-server.yml` (ansible-vault encrypted)

### PXE access setup
1. SSH key passphrase loaded via `ssh-add ~/.ssh/rui-desktop2`
2. Public key copied to `jc@pxe.cttb:~/.ssh/authorized_keys` via jump host
3. ProxyJump now works: `ssh -o ProxyJump=rui-desktop2 jc@pxe.cttb`
4. Inventory updated: `[pxe-server]` group in `hosts_os_upgrade.ini`

### Ansible compatibility issue
PXE server has only Python 3.5 (Ubuntu 16.04 Xenial). Ansible 2.20 requires 3.9+. Deadsnakes PPA doesn't support Xenial for 3.10+. Deployed role manually via SSH instead.

### netinstall-2404 deployed manually
Rendered Jinja2 templates locally, rsynced to server, installed via sudo:

- **Autoinstall profiles** → `/srv/netinstall/autoinstall/ubuntu/{desktop,server,desktop-minimal}/`
  - `user-data` — full autoinstall config (identity, SSH keys, packages, late-commands)
  - `meta-data` — empty (required by cloud-init)
- **PXE menu** → `/srv/netinstall/menu/ubuntu-live-server-amd64-noble.menu`
  - 3 entries: Desktop (lubuntu-desktop), Server, Desktop Minimal (lubuntu-core)
- **pxelinux config** → `/srv/netinstall/pxelinux.cfg/default`
  - Added "ubuntu live-server (amd64) - noble" submenu before existing entries
  - Backed up original to `default.bak`
- **ISO** — already present at `/var/www/html/ansible_assets/isos/ubuntu-24.04.2-live-server-amd64.iso`
  - Copied to `/srv/netinstall/ubuntu-live-server-noble-amd64.iso`
  - Extracted `casper/vmlinuz` and `casper/initrd` to `/srv/netinstall/ubuntu/live-server-noble-amd64/`
  - Symlinked ISO for HTTP serving
- **Post-install script** → `/srv/netinstall/autoinstall/postinst.sh`

### Verification
- All 3 autoinstall profiles serve via HTTP (200 OK)
- Kernel/initrd accessible via HTTP (200 OK)
- TFTP service active
- PXE menu has 10 labels (existing + new 24.04 entries)

### Repo changes
- `inventory/hosts_os_upgrade.ini` — added `[pxe-server]` group
- `inventory/group_vars/pxe-server.yml` — ansible-vault encrypted sudo password
- `roles/netinstall-2404/tasks/main.yml` — `include:` → `include_tasks:` (3 occurrences)

---

## USB Autoinstall Issues Found and Fixed

- **GRUB semicolon escaping:** `ds=nocloud;s=...` — GRUB treats `;` as command separator. Fixed by escaping as `\;` in grub.cfg. Used `perl -pi -e` because `sed` doesn't reliably preserve the backslash.
- **WiFi in autoinstall crashes installer:** Live-server ISO lacks WiFi firmware. `wifis` block in netplan causes `netplan apply` to fail fatally. Removed WiFi from USB user-data. Fix for templates: add `optional: true` to wifis block.
- **SQUASHFS corruption on USB:** The 59GB Flash Disk has flaky I/O — squashfs decompression errors during install. Same drive had I/O errors on 2026-04-17. **Need a different USB drive for future builds.**
- **Local apt mirror (apt.cttb) missing noble:** Mirror only has focal/xenial. Debootstrap and package installs must use `archive.ubuntu.com` over WAN.

---

## 2026-04-21 — dvgs-lab3 Installed via SSH Debootstrap

After USB autoinstall failed due to SQUASHFS corruption, installed Ubuntu 24.04 directly over SSH from the live installer shell:

1. **Partitioned NVMe** — wiped all partitions (Windows + old Ubuntu), created 512M EFI + 238G root
2. **Debootstrapped noble** — downloaded debootstrap 1.0.134 from archive.ubuntu.com (focal version lacked noble scripts), bootstrapped to /mnt
3. **Installed in chroot:**
   - linux-generic (6.8.0-110), grub-efi-amd64, shim-signed
   - openssh-server, python3, network-manager
   - lubuntu-desktop (Firefox snap skipped — snaps don't work in chroot, held with apt-mark)
4. **Configured:**
   - User `administrator` (UID 1000, password `a`, sudo NOPASSWD)
   - SSH keys: ansible@cttb.us RSA + jc ed25519
   - Hostname: dvgs-lab3
   - Timezone: US/Pacific
   - Default target: graphical
   - fstab with UUIDs
5. **GRUB installed** to EFI — warning about EFI vars not settable in chroot, may need manual boot menu selection on first boot
6. **Rebooted** — awaiting first boot verification

**Note:** UID is 1000 (not 999 as in autoinstall profile) because dnsmasq already had UID 999 in the debootstrap base. The cs-lab-2404 playbook should handle UID alignment.

**Still TODO on dvgs-lab3 after first boot:**
- [x] Verify GRUB boots correctly — confirmed, machine boots to Ubuntu 24.04
- [ ] Verify desktop loads (LightDM/SDDM + Lubuntu) — lubuntu-desktop installing via playbook (2026-04-30)
- [x] Configure WiFi (NetworkManager) for WAN access — connected to DRBU via nmcli (2026-04-30 session 1)
- [ ] Run `cs-lab-2404.yml` playbook for full CTTB config — in progress (2026-04-30 session 2, run 4)

---

## 2026-04-22 — UEFI PXE Boot, Theme Upload, Autoinstall Debugging

### Session Timeline

1. **Inspected dnsmasq DHCP config** — discovered PXE boot options already present (blocker from 04-21 was already resolved). Found both tagged (`tag:tftp`) and untagged `dhcp-boot` lines.
2. **Identified UEFI vs BIOS mismatch** — Dell Inspiron 5400 AIO F12 boot menu is UEFI-only, but PXE server only had `pxelinux.0` (BIOS). Needed GRUB EFI bootloader.
3. **Set up UEFI PXE boot** — extracted `grubx64.efi` from ISO (wrong one — no TFTP module), then got `grubnetx64.efi.signed` from `grub-efi-amd64-signed` package. Created GRUB config. Updated dnsmasq with architecture detection (`dhcp-match` for UEFI vs BIOS). GRUB menu appeared on dvgs-lab3.
4. **Changed SSH_AUTH_SOCK** — Bitwarden SSH agent was blocking `ssh-add`. Switched to macOS launchd agent: `SSH_AUTH_SOCK=$(launchctl getenv SSH_AUTH_SOCK)`.
5. **Hardened server access** — changed `jc` password to `a` on pxe.cttb and dnsmasq.cttb. Added `Match User jc` / `PasswordAuthentication no` to sshd_config on both servers. rui-desktop2 skipped (not a sudoer).
6. **Built and uploaded WhiteSur theme tarballs** — cloned 3 GitHub repos, packaged GTK (Light+Dark), icons (from src/), cursors (from dist/). Uploaded to `pxe.cttb:/var/www/html/ansible_assets/`. All serving HTTP 200.
7. **Verified avatar/background config** — group_vars correctly set per-site (`dvgs`, `dvbs`, `drbu`). Noted `desktop_login_background` var missing from dvbs/drbu group_vars (only have old `pic_bg`).
8. **Documented full deployment pipeline** — PXE install → post-boot setup → Ansible playbook → verification checklist.
9. **Debugged autoinstall failure** — kernel boots, ISO downloads, but installer drops to interactive mode. Cloud-init log showed `nocloud-net` deprecated in cloud-init 24.4. Changed to `ds=nocloud;seedfrom=URL` — still not triggering. Updated pxelinux menus too. **Unresolved — end of session.**

### Problem

Dell Inspiron 5400 AIO machines are UEFI-only (no legacy BIOS boot). The existing PXE infrastructure served `pxelinux.0` — a BIOS-only bootloader. UEFI clients selecting "Onboard NIC (IPV4)" from F12 boot menu received `pxelinux.0` which they couldn't execute.

### Discovery: DHCP PXE already configured

Inspected `/etc/dnsmasq.conf` on the DHCP server (dnsmasq.cttb). Found PXE boot options were **already present** — both a tagged and untagged `dhcp-boot` line pointing to `pxelinux.0` at `10.11.1.23`. The blocker from 2026-04-21 ("email sent to Frank") was already resolved.

### UEFI PXE setup

**On pxe.cttb (TFTP server at 10.11.1.23):**

1. Extracted `EFI/boot/grubx64.efi` from Ubuntu 24.04 ISO — **failed**: this is the local-disk GRUB binary, lacks TFTP module. GRUB loaded but dropped to shell with "disk 'tftp,10.11.1.23' not found."

2. Downloaded `grub-efi-amd64-signed` package, extracted `grubnetx64.efi.signed` — the **network-capable** GRUB binary with TFTP support built in. Placed at `/srv/netinstall/grubx64.efi`.

3. Created GRUB config at `/srv/netinstall/boot/grub/grub.cfg` (UEFI GRUB's `prefix` is `(tftp,10.11.1.23)/boot/grub` — discovered via `set` command in GRUB shell):

```
set default=0
set timeout=10

menuentry "Ubuntu 24.04 Desktop (CTTB)" {
    linux ubuntu/live-server-noble-amd64/casper/vmlinuz noprompt ip=dhcp ipv6.disable=1 url=http://pxe.cttb/netinstall/ubuntu-live-server-noble-amd64.iso autoinstall "ds=nocloud-net;s=http://pxe.cttb/netinstall/autoinstall/ubuntu/desktop/"
    initrd ubuntu/live-server-noble-amd64/casper/initrd
}
# + Server and Desktop Minimal entries
```

**On dnsmasq.cttb (DHCP server):**

4. Backed up `/etc/dnsmasq.conf` → `/etc/dnsmasq.conf.bak.20260422`

5. Replaced `dhcp-boot` lines with architecture-aware config:
```
# Architecture detection
dhcp-match=set:efi-x86_64,option:client-arch,7
dhcp-match=set:efi-x86_64,option:client-arch,9
dhcp-match=set:bios,option:client-arch,0
dhcp-boot=tag:efi-x86_64,grubx64.efi,,10.11.1.23
dhcp-boot=tag:bios,pxelinux.0,,10.11.1.23
```

6. Restarted dnsmasq — config test passed, service active.

### Files on PXE server

| File | Purpose |
|------|---------|
| `/srv/netinstall/grubx64.efi` | Network GRUB EFI binary (`grubnetx64.efi.signed` from `grub-efi-amd64-signed` package) |
| `/srv/netinstall/grubx64.efi.bak-local` | Backup of the non-network ISO-extracted binary (doesn't work for PXE) |
| `/srv/netinstall/boot/grub/grub.cfg` | UEFI GRUB menu config |
| `/srv/netinstall/grub/grub.cfg` | Copy of above (kept in sync) |

### Backups

| File | Location |
|------|----------|
| `/etc/dnsmasq.conf.bak.20260422` | dnsmasq.cttb — pre-UEFI dnsmasq config |
| `/etc/dnsmasq.conf.sed-bak` | dnsmasq.cttb — sed auto-backup |
| `/srv/netinstall/grubx64.efi.bak-local` | pxe.cttb — ISO-extracted GRUB (non-network) |

### Result

UEFI PXE boot fully working on dvgs-lab3. Machine selected "Onboard NIC (IPV4)" from F12 menu → received `grubx64.efi` via TFTP → loaded GRUB menu with 3 autoinstall options → Desktop selected → autoinstall running.

### Key lesson: `grubx64.efi` vs `grubnetx64.efi.signed`

- `grubx64.efi` from the ISO = local disk boot only, no network modules
- `grubnetx64.efi.signed` from `grub-efi-amd64-signed` package = has TFTP/HTTP modules for network boot
- The `prefix` GRUB variable reveals where it looks for config — use `set` at the GRUB shell to discover

### Access used

- **pxe.cttb**: `ssh jc@pxe.cttb` (direct, no jump host needed with key loaded)
- **dnsmasq.cttb**: `ssh jc@dnsmasq.cttb`, sudo password provided by user

### WhiteSur theme tarballs uploaded

Built from GitHub repos, uploaded to `pxe.cttb:/var/www/html/ansible_assets/`:

| File | Size | Contents |
|------|------|----------|
| `WhiteSur-gtk-theme.tar.gz` | 849K | `WhiteSur/` (Light) + `WhiteSur-Dark/` |
| `WhiteSur-icon-theme.tar.gz` | 6.6M | `WhiteSur/` (from src/) |
| `WhiteSur-cursors.tar.gz` | 1.7M | `WhiteSur-cursors/` (from dist/) |

All serve HTTP 200 at `http://pxe.cttb/ansible_assets/WhiteSur-*.tar.gz`.

### CURRENT BLOCKER: Autoinstall not triggering on 24.04

**Status:** UEFI PXE boot works (GRUB menu loads, kernel boots), but the Ubuntu installer drops to interactive mode instead of running autoinstall.

**Root cause investigation:**

1. First attempt used `ds=nocloud-net;s=URL` — cloud-init log showed `DataSourceNoCloud only uses seeds starting with ('/', 'file://') - will try to use http://... in the network stage` but then exited with "No local datasource found" and fell back to `DataSourceNone`. The `nocloud-net` datasource type was **deprecated in cloud-init 24.4** (shipped with Ubuntu 24.04).

2. Changed to `ds=nocloud;seedfrom=URL` (new syntax) — still drops to interactive installer. `/proc/cmdline` shows params are passed correctly. Not yet debugged with cloud-init logs on this attempt.

**Kernel cmdline (confirmed correct via /proc/cmdline):**
```
BOOT_IMAGE=/ubuntu/live-server-noble-amd64/casper/vmlinuz noprompt ip=dhcp ipv6.disable=1 url=http://pxe.cttb/netinstall/ubuntu-live-server-noble-amd64.iso autoinstall ds=nocloud;seedfrom=http://pxe.cttb/netinstall/autoinstall/ubuntu/desktop/
```

**What works:**
- UEFI PXE boot — GRUB menu loads ✓
- Kernel/initrd load via TFTP ✓
- ISO downloads via HTTP (`url=`) ✓
- Installer boots ✓
- user-data accessible at URL (HTTP 200, correct format) ✓

**What doesn't work:**
- cloud-init doesn't fetch user-data from network URL
- Installer falls back to interactive mode

**Next things to try:**
- Check cloud-init logs after `seedfrom=` attempt for specific error
- Try `ds=nocloud\;seedfrom=URL` with escaped semicolon (GRUB may be splitting on `;` despite quotes)
- Try `cloud-config-url=http://URL/user-data` as alternative kernel param
- Check if Ubuntu 24.04 subiquity requires `autoinstall` data embedded differently (e.g., in the ISO itself via `/cdrom/` path)
- Test whether the live installer's cloud-init even reaches the network stage before subiquity takes over

---

## 2026-04-23 — Autoinstall Datasource Fix (Attempt 3)

### Problem

Autoinstall still not triggering. PXE GRUB menu loads, kernel boots, ISO downloads, but installer drops to interactive language picker (screenshot confirmed). Same blocker as 04-22.

### Root Cause Analysis

Web research across multiple confirmed-working Ubuntu 24.04 PXE autoinstall setups revealed three issues with our kernel cmdline:

1. **Semicolon escaping method wrong**: We used `ds=nocloud\;s=URL` (backslash escape). All working GRUB configs use `ds="nocloud-net;s=URL"` (double-quote escaping). GRUB's `\;` may not pass the semicolon correctly to `/proc/cmdline`.

2. **Switched to `nocloud` too early**: We changed `nocloud-net` → `nocloud` based on the cloud-init 24.x deprecation notice. But every confirmed-working 24.04 PXE setup still uses `nocloud-net`. The deprecation warning is cosmetic — `nocloud-net` still works and `nocloud` alone may only look for local seeds, not network URLs.

3. **Missing `cloud-config-url=` fallback**: The Griffon's IT Library guide (the only confirmed-working example using ISO download via HTTP, same as our setup) uses **both** `ds="nocloud-net;s=URL/"` AND `cloud-config-url=URL/user-data` together. Belt-and-suspenders — if cloud-init's nocloud datasource fails to parse the ds= param, cloud-config-url provides a direct pointer to the user-data file.

### Sources

- [Griffon's IT Library — Ubuntu 24.04 Server PXE Autoinstall](https://c-nergy.be/blog/?p=20076) — uses `iso-url=` + `ds="cloud-net;s=URL"` + `cloud-config-url=URL/user-data`
- [Griffon's IT Library — Ubuntu 24.04 Desktop PXE Autoinstall](https://c-nergy.be/blog/?p=20051) — uses NFS boot + `cloud-config-url=URL`
- [Erwan Dufour — Ubuntu 24.04 PXE Autoinstall](https://erwan.dufour.io/devops/2024/08/31/autoInstallUbuntu.html) — uses NFS boot + `ds="nocloud-net;s=URL"` with double quotes
- [Kikyo-chan — Autoinstall Ubuntu 24.04 LTS](https://github.com/Kikyo-chan/Autoinstall-Ubuntu24.04-LTS-Server-and-Desktop) — iPXE with `ds=nocloud-net\;s=URL` + `cloud-config-url=/dev/null`

### Changes Made

**GRUB EFI template** (`roles/netinstall-2404/templates/pxe/grub-efi-2404.cfg.j2`):
```
# Before (attempt 2)
linux ... autoinstall ds=nocloud\;s={{ni_www}}/autoinstall/{{m.os}}/{{ai.name}}/

# After (attempt 3)
linux ... autoinstall ds="nocloud-net;s={{ni_www}}/autoinstall/{{m.os}}/{{ai.name}}/" cloud-config-url={{ni_www}}/autoinstall/{{m.os}}/{{ai.name}}/user-data
```

**Both pxelinux templates** (menu + default): same change, minus the quotes (semicolons aren't special in SYSLINUX):
```
APPEND ... autoinstall ds=nocloud-net;s={{ni_www}}/autoinstall/{{m.os}}/{{ai.name}}/ cloud-config-url={{ni_www}}/autoinstall/{{m.os}}/{{ai.name}}/user-data ---
```

**Also in this session (from previous session's unfinished work):**
- Added `optional: true` to wifi netplan block in all 3 user-data templates (fixes 04-17 installer crash)
- Added `ni_www` variable to defaults/main.yml
- Added GRUB EFI config directory + template tasks to pxe.yml

### Rendered GRUB line for PXE server

```
linux ubuntu/live-server-noble-amd64/casper/vmlinuz noprompt ip=dhcp ipv6.disable=1 url=http://pxe.cttb/netinstall/ubuntu-live-server-noble-amd64.iso autoinstall ds="nocloud-net;s=http://pxe.cttb/netinstall/autoinstall/ubuntu/desktop/" cloud-config-url=http://pxe.cttb/netinstall/autoinstall/ubuntu/desktop/user-data
```

### Status

Templates updated in repo. **Not yet deployed to PXE server** — need to SSH in and update `/srv/netinstall/boot/grub/grub.cfg` with the rendered line above, then PXE reboot dvgs-lab3.

---

## 2026-04-23 — Core Services Audit & Gitolite Access

### Infrastructure Access Audit

Performed a full audit of all CTTB core infrastructure to map services and establish SSH access. Started from `administrator@dnsmasq.cttb` (password `4m1t0f0`) — discovered most hosts are pubkey-only.

**Access path discovered:**
1. `~/.ssh/rui-desktop2` key is passphrase-protected (AES-256-CTR, bcrypt). Passphrase: `a` (loaded via `expect` + `ssh-add`).
2. rui-desktop2 → `johnchandara` account → can see `/home/kit.chong` but can't sudo (password unknown).
3. Added ed25519 pubkey directly to `administrator@srv-vm.cttb` and `administrator@srv-gw.cttb` (manually by user).
4. Later added pubkey to `administrator@srv-nas.cttb`.

### srv-vm (10.11.1.3) — Primary LXD Host

Ubuntu 16.04. Runs 15 LXC containers:

| Container | IP | OS | Services |
|-----------|-----|-----|----------|
| dnsmasq | 10.11.1.19 | 16.04 | dnsmasq (DHCP+DNS) |
| ldap | 10.11.1.25 | 16.04 | slapd (OpenLDAP) |
| asterisk | 10.11.6.1 / 10.11.1.32 | 16.04 | asterisk, apache2, tftpd-hpa |
| cups-cttb | 10.11.1.36 | 16.04 | cups, colord |
| cups-dvbs | 10.11.1.37 | 16.04 | cups, colord |
| cups-dvgs | 10.11.1.38 | 16.04 | cups, colord |
| ub-adult | 10.11.1.29 | 16.04 | unbound (DNS filter) |
| ub-igdvs | 10.11.1.28 | 16.04 | unbound (DNS filter, schools) |
| jumpbox | 10.11.1.33 + 10.11.100.1 | 16.04 | openvpn@server |
| wiki | 10.11.1.31 | 16.04 | apache2, mysql, php7.0-fpm |
| blogger | 10.11.1.42 | 16.04 | ghost_blogger-cttb, nginx, mysql |
| drbu-sis | 10.11.1.41 | 16.04 | nginx, mariadb, php7.4-fpm |
| sltp | 10.11.1.39 | **22.04** | apache2, postgresql@{10..18}-main, sendmail |
| sltp-git | 10.11.1.40 | **18.04** | koha-common, elasticsearch, mariadb, memcached, rabbitmq, apache2, postfix |
| mon | 10.11.1.26 | 16.04 | (no app services detected) |

### srv-nas (10.11.1.5) — Secondary LXD Host

Ubuntu 16.04. Runs 6 containers + 1 stopped:

| Container | IP | OS | Services |
|-----------|-----|-----|----------|
| git | 10.11.1.21 | 16.04 | apache2 (gitweb), gitolite3 |
| koha | 10.11.1.27 | 16.04 | koha-common, apache2, mysql, memcached |
| fs | 10.11.1.18 | 16.04 | nfs-mountd, rpcbind, quotarpc, apache2 |
| pxe | 10.11.1.23 | 16.04 | apache2, tftpd-hpa |
| debmirror | 10.11.1.22 | 16.04 | apache2 |
| log | 10.11.1.20 | 16.04 | sfcapd (NetFlow) |
| metrics | — | — | **STOPPED** |

### srv-gw (10.11.1.1) — Gateway/Firewall

Ubuntu 16.04. Services: squid (proxy), e2guardian (content filter), ulogd2 (firewall logging), ntp, mdadm, smartd.

### Gitolite Access Established

`git.cttb` resolves to 10.11.1.21 (container `git` on srv-nas). Runs **Gitolite 3.6.4** + gitweb.

**Problem:** Gitolite's `update` hook was broken — Perl couldn't find `Gitolite::Hooks::Update` module (`@INC` missing gitolite lib path). Push via `gitolite-admin.git` clone failed.

**Fix:** Added pubkey directly to gitolite keydir and recompiled:
```bash
lxc exec git -- sh -c '
  echo "PUBKEY" > /srv/gitolite/.gitolite/keydir/jc.pub
  chown git:git /srv/gitolite/.gitolite/keydir/jc.pub
  su - git -c "gitolite compile; gitolite trigger POST_COMPILE"
'
```

**Result:** Full R/W access to all repos as `jc`:
```
ansible-conf, ansible-files-conf, ansible-new, asterix, dnsmasq,
nagios, snmp-lldp, testing, unattended-install, utils
```

Clone: `git clone git@git.cttb:ansible-new`

### Infographic

Generated `cttb-core-services.html` — interactive HTML dashboard showing all 24 core hosts with service details, IPs, OS versions, and access status.

### Hosts still inaccessible

- **srv-bk-nas** (10.11.1.11) — powered off
- **srv-bk-vm** (10.11.1.7) — powered off
- **metrics** container on srv-nas — stopped

---

## 2026-04-30 — Add Noble to apt.cttb debmirror

### Context

All 24.04 playbook runs require `deb_mirror=http://archive.ubuntu.com` because the local apt mirror only has focal and xenial. This pulls 1GB+ over WAN per machine — blocker for mass rollout.

### What was done

1. **Probed debmirror container** (10.11.1.22, Ubuntu 16.04):
   - 4.0 TB free disk, debmirror v2.25 (2016)
   - Existing dists: focal + xenial (both with -security/-updates/-backports)
   - Focal was added manually by Rui in 2022, not through the ansible role

2. **GPG key for noble** — Ubuntu Archive Signing Key (2018) `991BC93C` was already in the keyring. Verified it signs the noble Release file.

3. **Tested debmirror v2.25 compatibility** — dry run with `--dry-run -d noble -s main` succeeded. Old binary handles noble Release format fine.

4. **Created `/srv/debmirror/scripts/dm-ubuntu-24.04.sh`** on container:
   - Matches Rui's pattern from `dm-ubuntu-20.04.sh`
   - Uses `--nocleanup` so noble packages coexist with focal/xenial in shared pool
   - Sections: main,restricted,universe,multiverse + debian-installer variants
   - Releases: noble,noble-security,noble-updates,noble-backports

5. **Added to `/srv/debmirror/scripts/runall.sh`** — noble script runs alongside 16.04/20.04 in nightly cron (1:00 AM)

6. **Kicked off initial sync** — started 2026-04-30 14:29 PDT. Will take several hours. Progress in `/srv/debmirror/log/ubuntu-24.04.log`.

7. **Updated ansible role** (`roles/debmirror/`):
   - `defaults/main.yml`: Added focal and noble entries alongside xenial (was out of sync with container reality)
   - `templates/debmirror.j2`: Added `--nocleanup` support via `nocleanup` variable

### Current sync state (as of 2026-04-30 14:48 PDT)

- **Sync running** on container PID 4677. Sections: `main,restricted,universe,multiverse`. Releases: `noble,noble-security,noble-updates`. No backports, no d-i sections.
- Sync is incremental — was restarted twice (first with all sections + d-i + backports, then trimmed). Already-downloaded packages are skipped.
- Expect several hours for initial sync to complete.

---

## 2026-04-30 — dvgs-lab3 Ansible Playbook Debugging

### Changes Made

1. **Inventory cleanup**: Fixed the IP address for `dvgs-lab3.cttb` to `10.11.9.23` in `inventory/hosts_os_upgrade.ini` and removed duplicate entries for dvgs-lab1 through dvgs-lab9.
2. **Network config**: Connected `dvgs-lab3.cttb` to the `DRBU` WiFi network via SSH (`nmcli`) to provide WAN access for package downloads.
3. **Ansible Playbook Fixes for Ubuntu 24.04 (Noble)**:
   - Ran with `deb_mirror=http://archive.ubuntu.com` as the local `apt.cttb` mirror lacks noble packages.
   - **time-server role**: Resolved `systemd-timesyncd` vs `ntp` conflict. Added tasks to explicitly stop and remove `systemd-timesyncd` before installing `ntp`.
   - **common role (NetworkManager)**: Added a task to create `/etc/NetworkManager/conf.d` directory before attempting to write the `ethernet-wake-on-lan.conf` file.
   - **common role (Packages)**: 
     - Replaced deprecated `exfat-utils` with `exfatprogs`.
     - Removed `hddtemp` as it is no longer available in the Ubuntu 24.04 repositories.
     - Replaced `iptraf` with `iptraf-ng`.

### Status

- Phase 3 Ansible playbook (`cs-lab-2404.yml`) execution was started but is currently hanging at the `refresh the mirrors` (apt update) step. This needs to be investigated in the next session (it may be waiting for an interactive prompt or experiencing a network timeout). The background playbook process has been terminated.

---

## 2026-04-30 — Playbook Hang Root Cause & Fixes (Session 2)

### Root Cause: Playbook Hang

**`needrestart`** — installed by default on Ubuntu 24.04, hooks into apt's `DPkg::Post-Invoke`. After any package install/upgrade, it prompts interactively asking which services to restart. Ansible has no TTY → hangs forever. This is a known issue with 24.04 automation.

### Fixes Applied

1. **needrestart disabled for Ansible** (`roles/common/tasks/setup/default.yml`, `roles/common/files/conf/needrestart-auto.conf`)
   - Deploys `/etc/needrestart/conf.d/50-autorestart.conf` with `$nrconf{restart} = 'a'` (auto-restart, no prompt)
   - Task runs before any apt operations
   - Also added `DEBIAN_FRONTEND=noninteractive` + `NEEDRESTART_MODE=a` as play-level environment in `plays/cs-lab-2404.yml`

2. **apt sources deb822 format** (`roles/common/templates/ubuntu.sources.j2`, `roles/common/tasks/setup/default.yml`)
   - Ubuntu 24.04 uses `/etc/apt/sources.list.d/ubuntu.sources` (deb822 format), not `/etc/apt/sources.list`
   - Both files existed → duplicate repo warnings on every `apt update`
   - New template `ubuntu.sources.j2` for 24.04+; legacy `sources.list.j2` for pre-24.04
   - On 24.04+, `/etc/apt/sources.list` is blanked with a comment pointing to the deb822 file

3. **jc SSH key deployed** (`roles/common/files/ssh_keys/jc.pub`)
   - ed25519 pubkey added to `authorized_key` task in common role
   - Only ansible RSA key was previously deployed; now both are managed

4. **NOPASSWD sudo configured** on dvgs-lab3 (was missing after debootstrap install)

5. **Ubuntu_24 platform stubs** (`roles/common/tasks/setup/Ubuntu_24.yml`, `roles/common/vars/Ubuntu_24.yml`, `roles/desktop/tasks/setup/Ubuntu_24.yml`, `roles/desktop/vars/Ubuntu_24.yml`)
   - Ansible 2.20 treats `first_found` with `skip:true` returning empty as fatal in `include_tasks`
   - Created empty/minimal stub files for both roles

6. **mlocate → plocate** (`roles/common/vars/Ubuntu_24.yml`)
   - `mlocate` removed from Noble repos; `plocate` is the replacement

7. **polkit pkla → JavaScript rules** (`roles/desktop/tasks/setup/default.yml`, `roles/desktop/files/config/*.rules`)
   - Ubuntu 24.04 dropped `pklocalauthority` backend; `/var/lib/polkit-1/localauthority/` doesn't exist
   - Created `.rules` equivalents for NetworkManager restrictions and root power-off permissions
   - Deploy `.rules` on 24.04+, keep `.pkla` for pre-24.04

### Playbook Runs

| Run | ok | changed | failed | Failure |
|-----|----|---------| -------|---------|
| 1 | 36 | 11 | 1 | `first_found`+`skip:true` → empty include (no Ubuntu_24.yml) |
| 2 | 28 | 2 | 1 | `mlocate` package not available on Noble |
| 3 | 41 | 5 | 1 | polkit `localauthority` dir missing on 24.04 |
| 4 | 58 | 12 | 1 | `desktop_shortcuts` loop on undefined var (not a list) |
| 5 | 58 | 6 | 1 | Same as run 4 — `default([])` doesn't help when var is defined as `false` |
| 6 | 75 | 20 | 1 | `/etc/xdg/menus/lxqt-applications.menu` missing (Lubuntu 24.04 uses lxde menu) |
| 7 | 87 | 12 | 1 | `libreoffice-gtk` no install candidate (virtual pkg on Noble) |
| 8 | 90 | 7 | 1 | Chrome repo uses `deb_mirror` — breaks when overridden to archive.ubuntu.com |
| 9 | 89 | 5 | 1 | Chrome signing key HTTPS unreachable (dl.google.com blocked by firewall) |
| 10 | 90 | 5 | 1 | Chrome mirror GPG key expired on apt.cttb (`EXPKEYSIG`) |
| 11 | 89 | 5 | 1 | Firefox snap tries snap store for 30min, fails (no HTTPS egress) |
| 12 | 90 | 5 | 1 | VS Code key HTTPS unreachable (same no-egress issue) |
| 13 | 94 | 8 | 1 | pulseaudio system service fails on 24.04 (per-user mode now) |
| 14 | 105 | 12 | 1 | `/etc/cups` dir missing — default printer task outside block |
| 15 | 105 | 7 | 1 | `ldap_clients` group missing from inventory |
| 16 | 122 | 22 | 1 | `ldap_group_acl_string` undefined — no site-level `[dvgs]` group |
| **17** | **144** | **27** | **0** | **PASSED** — all 5 roles complete (browsers/vscode skipped) |

### All Fixes (in order)

8. **desktop_shortcuts default** — changed `false` → `[]` in `roles/desktop/defaults/main.yml`. Ansible 2.20 evaluates `loop:` before `when:`.
9. **lxqt menu guard** — `stat` check in `roles/desktop/tasks/app-menu.yml`. Lubuntu 24.04 uses `lxde-applications.menu`.
10. **libreoffice-gtk → libreoffice-gtk3** — virtual package with no candidate on Noble.
11. **Chrome repo/key URLs → apt.cttb** — decoupled from `deb_mirror` override, use `apt_url` for internal mirror. Key and repo both served over HTTP.
12. **jc SSH key in netinstall** — added `ni_jc_ssh_pubkey` to all 3 autoinstall user-data templates.
13. **pulseaudio system service skipped on 24.04+** — PipeWire/PulseAudio runs per-user now. `roles/desktop/tasks/sound.yml`.
14. **cups-client block fix** — `set default printer` task was outside the `cups_srv` block, ran before `/etc/cups` was created.
15. **`ldap_clients` inventory group** — ldap-client role asserts membership; group missing from `hosts_os_upgrade.ini`.
16. **Site-level parent groups** (`[dvgs]`, `[dvbs]`, `[drbu]`) — needed for `group_vars/dvgs` etc. to load (provides `ldap_group_acl_string` and other site vars).
17. **lxqt-applications.menu symlink** — Lubuntu 24.04 only ships `lxde-applications.menu`; LXQt panel expects `lxqt-applications.menu`. Symlink on 24.04+.
18. **Panel icon theme** — `lxpanel.j2` hardcoded `windos10-icons`; changed to `{{icon_theme}}` variable.
19. **Window manager: openbox → xfwm4** — Openbox has no GTK theme integration (separate theme format, rarely supported by modern themes like WhiteSur). xfwm4 uses WhiteSur's native `xfwm4/` theme for consistent window decorations, includes a built-in compositor (shadows, transparency), and supports macOS-style button layout (close/min/max on left). ~15MB resident, mature since 2003.
20. **Login backgrounds** — per-site wallpapers from 512pixels.net: High Sierra (dvgs), Sequoia Sunrise (dvbs), Yosemite (drbu).
21. **xserver-xorg** — missing because `install_recommends: no` skips it. Added explicitly to lubuntu.yml.

---

## 2026-04-30 — Fix Expired Chrome GPG Key on apt.cttb Mirror

### Problem

Chrome repo mirror at `http://apt.cttb/mirrors/chrome` had an expired GPG signing key (`EXPKEYSIG 4EB27DB2A3B88B8B`). The `InRelease` file was signed with subkey `A3B88B8B` (expired 2024-10-25). `apt-get update` failed on any machine with the Chrome repo configured. This was blocker #10 from the playbook debugging series (run 10: `EXPKEYSIG`).

The mirror hadn't synced successfully since **Feb 2024** — packages were Chrome 121 stable.

### Root Cause

The debmirror GPG keyring (`/srv/debmirror/gpg/trustedkeys.gpg`) only had older subkeys for Google's signing key (`D38B4796`). The newest signing subkey `A6BC6E42` (valid 2024-01-30 → 2027-01-29) was not present, so `gpgv` rejected the fresh `InRelease` downloaded from Google and debmirror refused to promote files from `.temp/`.

### Fixes Applied

**On debmirror container** (10.11.1.22, via `lxc exec debmirror` on srv-nas):

1. **Downloaded fresh Google signing key:**
   ```bash
   curl -s https://dl.google.com/linux/linux_signing_key.pub -o /tmp/google-key-new.pub
   ```

2. **Imported into debmirror GPG keyrings** — both `pubring.gpg` and `trustedkeys.gpg`:
   ```bash
   GNUPGHOME=/srv/debmirror/gpg gpg --import /tmp/google-key-new.pub
   GNUPGHOME=/srv/debmirror/gpg gpg --no-default-keyring --keyring trustedkeys.gpg --import /tmp/google-key-new.pub
   ```
   Imported 4 new subkeys + 5 new signatures. Key subkeys now include:
   - `A6BC6E42` (2024-01-30 → 2027-01-29) — **current signing key**
   - `C264648F` (2025-01-07 → 2028-01-07)
   - `006FEAB8` (2026-03-10 → 2029-03-09)

3. **Fixed file ownership** — initial root import changed `pubring.gpg` to `root:root`, breaking debmirror user access:
   ```bash
   chown debmirror:debmirror /srv/debmirror/gpg/pubring.gpg
   chown debmirror:debmirror /srv/debmirror/gpg/trustedkeys.gpg
   ```

4. **Re-ran Chrome mirror sync** (`/srv/debmirror/scripts/dm-chrome.sh` as debmirror user):
   - Downloaded 492 MiB (4 new .deb packages)
   - Chrome stable 121 → **147.0.7727.137**
   - Chrome beta → **148.0.7778.96**
   - Chrome canary → **149.0.7818.0**
   - Chrome unstable → **149.0.7815.2**
   - `InRelease` updated from Feb 1 2024 → Apr 30 2026

5. **Updated public signing key files:**
   ```bash
   cp /tmp/google-key-new.pub /var/www/html/Google-linux_signing_key.pub
   cp /tmp/google-key-new.pub /var/www/html/google.key
   ```

### Verification

```
$ curl -sI http://apt.cttb/mirrors/chrome/dists/stable/InRelease | head -5
HTTP/1.1 200 OK
Last-Modified: Thu, 30 Apr 2026 21:16:37 GMT

$ curl -sI http://apt.cttb/Google-linux_signing_key.pub | head -5
HTTP/1.1 200 OK
Last-Modified: Fri, 01 May 2026 03:16:11 GMT
```

### Key Lesson: `trustedkeys.gpg` vs `pubring.gpg`

debmirror uses `gpgv` for signature verification, which reads from `trustedkeys.gpg` — **not** `pubring.gpg`. Importing a key into `pubring.gpg` alone is insufficient. Both keyrings must be updated.

### Impact on Playbook

The Chrome `EXPKEYSIG` blocker (run 10) is now resolved. The `sw-browser.yml` task that adds the Chrome repo and key from `apt.cttb` should now succeed. Chrome can be re-enabled in playbook runs (remove `-e "chrome=false"`).

---

## 2026-05-01 — Global Application Menu (macOS-style menu bar)

### What was done

Installed and configured `xfce4-appmenu-plugin` on dvgs-lab3 to add a macOS-style global application menu to the top panel. When an app is focused, its menu bar (File, Edit, View, etc.) appears in the top panel instead of the app's title bar — matching the SmallSur/macOS look.

### Packages installed

| Package | Version | Purpose |
|---------|---------|---------|
| `xfce4-appmenu-plugin` | 0.7.6+dfsg1-4build4 | XFCE4 panel plugin for global menu |
| `appmenu-gtk3-module` | 0.7.6-2.1ubuntu2 | GTK3 module that exports app menus to DBus |
| `appmenu-registrar` | 0.7.6-2build2 | DBus service that registers app menus |
| `vala-panel-appmenu-common` | 0.7.6+dfsg1-4build4 | Shared config/data files |
| `appmenu-gtk-module-common` | 0.7.6-2.1ubuntu2 | Systemd user service for GTK module |
| `libappmenu-gtk3-parser0` | 0.7.6-2.1ubuntu2 | Shared library for menu parsing |

All from Ubuntu noble/universe. Installed via manual `.deb` download (proxy was down due to `timed_internet.sh` schedule).

### Panel layout

**Top bar** (panel-1, 26px, full width):
- Lotus icon + hostname → **appmenu** (global menu) → expanding spacer → tasklist → systray → clock → actions

**Bottom dock** (panel-2, 48px, autohide):
- Show desktop → terminal → file manager → web browser → separator → home directory menu

### Ansible role changes

1. **`roles/desktop/tasks/lubuntu.yml`** — added `xfce4-panel`, `xfce4-appmenu-plugin`, `appmenu-gtk3-module`, `appmenu-registrar` to package list
2. **`roles/desktop/templates/xfce4-panel.xml.j2`** — new template for XFCE4 panel config with global menu plugin, templatized hostname (`{{inventory_hostname_short}}`)
3. **`roles/desktop/tasks/lookandfeel.yml`** — added task to deploy `xfce4-panel.xml.j2` to `/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/`

### Notes

- The `appmenu-gtk-module-common` package creates systemd user service symlinks for `xfce-session.target`, `mate-session.target`, and `gnome-session.target`. The xfce-session.target warning is cosmetic — the GTK module loads via environment variable, not systemd.
- Global menu works for GTK3 apps out of the box. GTK2 apps need `appmenu-gtk2-module` (not installed — most apps are GTK3+ now). Qt5 apps need `appmenu-qt5` (recommend installing if KDE/Qt apps are used).
- The panel XML is deployed to `/etc/xdg/` (system default). Per-user config in `~/.config/xfce4/` takes precedence — existing users won't see changes until their local config is removed or the panel is reset.
- Temporary autologin was added to `/etc/lightdm/lightdm.conf` to bypass the greeter for testing, then removed after screenshot.

### Right-side widgets (SmallSur-matching)

Updated the top panel right side to match the [SmallSur](https://github.com/jothi-prasath/SmallSur) XFCE rice. Reference: `SmallSur/xfce4-panel/xfce4-panel.xml`.

**Before:** systray → bare clock → actions (logout/power buttons)
**After:** systray → separator → volume → power → notifications → clock → separator

| Plugin | Type | Config |
|--------|------|--------|
| `pulseaudio` | Volume control | MPRIS enabled, keyboard shortcuts, pavucontrol mixer |
| `power-manager-plugin` | Power/battery icon | Default config |
| `notification-plugin` | Notification bell | Default config |
| `clock` | Date + time | `%a %d %b %l:%M %p` (e.g. "Thu 01 May 6:30 AM") |

Removed `actions` plugin — logout/shutdown accessible via the lotus (applications) menu.

Additional packages added to `lubuntu.yml`: `xfce4-pulseaudio-plugin`, `xfce4-notifyd`.

### SSH access notes

- `SSH_AUTH_SOCK=/var/run/com.apple.launchd.rwA60yzqH5/Listeners` — macOS default ssh-agent socket (Bitwarden had hijacked it via `launchctl setenv`)
- `ssh -A -J cttb administrator@dvgs-lab3.cttb` — agent forwarding required; ProxyJump alone doesn't forward the key
- `sudo XAUTHORITY=/var/run/lightdm/root/:0 DISPLAY=:0 import -window root /tmp/screenshot.png` — screenshot via ImageMagick (xfce4-screenshooter not installed)

---

## 2026-05-01 — Wallpaper Rotation: cron+feh → xfdesktop native

### What changed

Replaced the cron+feh wallpaper rotation with XFCE's built-in `xfdesktop` backdrop cycling. No external dependencies needed — xfdesktop handles image rotation natively.

### Files modified

| File | Change |
|------|--------|
| `roles/desktop/templates/xfce4-desktop.xml.j2` | **NEW** — xfdesktop config with wallpaper dir, cycling interval, random order |
| `roles/desktop/tasks/wallpaper.yml` | Replaced feh install + cron deploy with xfce4-desktop.xml template deploy + legacy cleanup |
| `roles/desktop/defaults/main.yml` | `desktop_wallpaper_interval_hours: 6` → `desktop_wallpaper_interval_minutes: 360` |
| `host_vars/dvgs-lab3.cttb` | Added `desktop_wallpaper_interval_minutes: 1` (testing) |

### How it works

xfdesktop reads `/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml` and cycles through images in `desktop_wallpaper_dir` at the configured interval. Properties:

- `last-image` → points to wallpaper directory (xfdesktop scans for images)
- `backdrop-cycle-enable` → enables cycling
- `backdrop-cycle-period` → interval in minutes
- `backdrop-cycle-random-order` → randomize selection

**Note:** xfdesktop 4.18+ (Ubuntu 24.04) uses `backdrop-cycle-*` property names. The older `image-show`/`image-period` names do not work. Monitor property must match xrandr output name (e.g. `monitorHDMI-1`).

### macOS tarball cleanup

The `cttb-wallpapers.tar.gz` was created on macOS and contains `._` resource fork files. These are cleaned up by the wallpaper task (`rm -f ._*`).

### Legacy cleanup

The wallpaper task now removes:
- `/etc/cron.d/wallpaper-rotation` (old cron job)
- `/usr/local/bin/rotate-wallpaper.sh` (old feh script)

`feh` package removed from dependencies (was only needed for wallpaper rotation).

### Testing

dvgs-lab3 set to 1-minute rotation for testing. All other hosts default to 360 minutes (6 hours).

---

## 2026-05-01 — Thunderbird Email Client (Mozilla tarball)

### Problem

Ubuntu 24.04's `thunderbird` apt package is a snap transition wrapper. Snap store is unreachable on campus. Mozilla Team PPA (`ppa.launchpad.net`) is also unreachable — blocked at the network/firewall level (not just e2guardian).

### Solution

Downloaded official Mozilla tarball, hosted on `pxe.cttb/ansible_assets/`.

| Component | Detail |
|-----------|--------|
| Source | `https://download.mozilla.org/?product=thunderbird-latest-ssl&os=linux64&lang=en-US` |
| Version | 150.0.1 |
| Asset | `http://pxe.cttb/ansible_assets/thunderbird-latest.tar.xz` (78MB) |
| Install path | `/opt/thunderbird/` |
| Binary | `/usr/local/bin/thunderbird` (symlink) |

### Files

| File | Change |
|------|--------|
| `roles/desktop/tasks/sw-thunderbird.yml` | **NEW** — removes snap wrapper, extracts tarball, symlinks binary, deploys .desktop |
| `roles/desktop/tasks/sw.yml` | Added `include_tasks: sw-thunderbird.yml` |
| `roles/desktop/defaults/main.yml` | Added `thunderbird: true` |

### Network investigation

- `ppa.launchpad.net` resolves but IPv4 connections timeout from all campus hosts (debmirror container, dvgs-lab3, Mac)
- `ppa.launchpadcontent.net` blocked by e2guardian (added to exceptions but still blocked at IP level)
- `archive.mozilla.org` also blocked through campus proxy
- Only internal hosts (`apt.cttb`, `pxe.cttb`) and whitelisted external hosts (`dl.google.com`, `archive.ubuntu.com`) are reachable
- Downloaded on Mac bypassing proxy (`--noproxy '*'`), SCP'd to pxe.cttb

### Updating Thunderbird

To update: download new tarball from Mozilla, upload to `pxe.cttb/ansible_assets/thunderbird-latest.tar.xz` (overwrite), re-run playbook. The `creates:` guard checks for `/opt/thunderbird/thunderbird` — delete it first to force re-extract, or remove the `creates:` line.

### Also done (for future PPA use)

- Added `launchpadcontent.net` to e2guardian exception list on srv-gw
- Added `mozillateam` entry to `host_vars/lxc-debmirror` debmirror config
- Imported Mozilla Team PPA GPG key into debmirror keyrings on apt.cttb
- These are ready for when the firewall is updated to allow Launchpad IPs

---

## 2026-05-01 — Hostname, Fonts, NTP, Content Filter

### Hostname rename

Renamed `dvgs-lab3` → `dvgs-testmachine` across all inventories and host_vars to distinguish the test machine from the production lab fleet.

| File | Change |
|------|--------|
| `inventory/hosts` | Renamed both host entry and `dvgs_cs_lab` group member |
| `inventory/hosts_os_upgrade.ini` | Renamed in MAC/IP list and `dvgs_cs_lab` group |
| `host_vars/dvgs-lab3.cttb` → `host_vars/dvgs-testmachine.cttb` | File renamed |

### Inter Display font

Switched all desktop font references from Inter → Inter Display (better optical sizing for UI).

| File | Change |
|------|--------|
| `roles/desktop/defaults/main.yml` | `desktop_font` and `desktop_title_font` → Inter Display |
| `roles/desktop/templates/lightdm-gtk-greeter.j2` | Login screen font → Inter Display |
| `roles/desktop/templates/lxqt-conf.j2` | Qt font → Inter Display |
| `roles/desktop/files/config/gtk-panel.css` | Panel CSS font-family → Inter Display |
| `roles/desktop/tasks/lookandfeel.yml` | **NEW task** — installs Inter Display TTFs from `pxe.cttb/ansible_assets/InterDisplay.tar.gz` |
| `roles/desktop/handlers/main.yml` | Added `rebuild font cache` handler |

Asset uploaded to PXE server: `/var/www/html/ansible_assets/InterDisplay.tar.gz` (3.5MB, 18 TTF files from Inter v4.1).

### NTP / time-server role for Ubuntu 24.04

Ubuntu 24.04 removed the `ntp` package. Updated `time-server` role to use `systemd-timesyncd` on 24.04+, keeping legacy `ntp` for older Ubuntu.

| File | Change |
|------|--------|
| `roles/time-server/tasks/main.yml` | Added 24.04+ block (remove legacy ntp, install/configure timesyncd) |
| `roles/time-server/templates/timesyncd.conf.j2` | **NEW** — configures NTP servers from `ntp_servers` var |
| `roles/time-server/handlers/main.yml` | Added `restart timesyncd` handler |
| `plays/cs-lab-2404.yml` | Added `time-server` role |

### Content filter — temporary unrestricted

Added `dvgs-testmachine` (10.11.9.23) to the `adult` e2guardian filter group in `host_vars/srv-gw` for testing. **Must revert before mass deployment** (tracked in backlog).

---

## 2026-05-01 — Desktop Polish: Shadows, Fonts, Panel, Terminal Theme

### Desktop icon text shadows

Added `show-icon-label-shadows` xfconf property to `xfce4-desktop.xml.j2`. Confirmed working via remote screenshot on dvgs-lab3 — subtle shadow behind icon labels improves readability on light wallpapers.

Attempted bold via GTK CSS (`.xfdesktop-icon-view { font-weight: 700 }`), but xfdesktop 4.18 renders labels with Cairo/Pango, ignoring GTK CSS. Pivoted to system font weight: `desktop_font` → `Inter Display Semi-Bold 11`.

### Panel config pulled from live machine

Pulled xfconf panel config from dvgs-testmachine (dvgs-lab3 went offline mid-session). Major changes from previous template:

| Setting | Before | After |
|---------|--------|-------|
| Panel count | 2 (top bar + dock) | 1 (top bar only) |
| Size | 26px | 24px |
| Autohide | off | on |
| Background | default | semi-transparent dark (rgba 0.15/0.11/0.11/0.54) |
| Appmenu | no options | bold-application-name, expand |
| Clock font | default | Inter Display Semi-Bold 10 |
| Tasklist | present | removed |
| Plugin-1 title | hostname | hostname (via Jinja `inventory_hostname_short`) |

### Window titles

- `desktop_title_font` → `Inter Display Bold 10`
- Added `title_alignment: left` to `xfwm4.xml.j2`
- Confirmed working live via xfconf-query on dvgs-testmachine

### Chrome rounded corners

Added task in `sw-browser.yml` to patch `google-chrome-stable.desktop` with `--use-system-title-bar`, forcing Chrome to use xfwm4's WhiteSur-Dark window frame (which has rounded corners).

### xfce4-terminal Man Page theme

Translated macOS Terminal.app "Man Page" profile (`.terminal` plist) to xfce4-terminal `terminalrc`:

| Setting | Value |
|---------|-------|
| Font | Ubuntu Mono 12 |
| Background | `#f3eb8a` (warm yellow) |
| Foreground | `#000000` (black) |
| Cursor | `#8b8b8b` (gray) |
| Selection | `#bfb875` (olive) |
| Scrollbar | hidden |

Full 16-color ANSI palette included. Deployed to `/etc/xdg/xfce4/terminal/terminalrc`. Added `xfce4-genmon-plugin` to package list in `lubuntu.yml`.

### Wallpaper config

- Changed monitor target from `monitorscreen` to `monitorHDMI-1` (matches Dell AIO hardware)
- Updated wallpaper rotation to use `backdrop-cycle-*` properties
- Added task to clean macOS resource fork files (`._*`) from wallpaper directory

### Files changed

| File | Change |
|------|--------|
| `roles/desktop/defaults/main.yml` | Font → Inter Display Semi-Bold 11, title → Inter Display Bold 10 |
| `roles/desktop/templates/xfce4-panel.xml.j2` | Full rewrite from live config |
| `roles/desktop/templates/xfwm4.xml.j2` | Added title_alignment=left |
| `roles/desktop/templates/xfce4-desktop.xml.j2` | monitorHDMI-1, backdrop-cycle, icon shadows |
| `roles/desktop/files/config/gtk-panel.css` | font-family → Inter Display |
| `roles/desktop/files/config/terminalrc` | **NEW** — Man Page theme |
| `roles/desktop/files/config/panel-hostname.sh` | **NEW** — genmon hostname script |
| `roles/desktop/tasks/lookandfeel.yml` | Added terminal config + hostname script deploy tasks |
| `roles/desktop/tasks/sw-browser.yml` | Chrome --use-system-title-bar |
| `roles/desktop/tasks/lubuntu.yml` | Added xfce4-genmon-plugin |
| `roles/desktop/tasks/wallpaper.yml` | Clean macOS resource forks |

### Test deployment

Deployed to dvgs-testmachine.cttb, verified via remote screenshots:
- Panel: semi-transparent, autohide, lotus icon, clock working
- Window titles: bold, left-aligned, WhiteSur-Dark traffic lights
- Terminal: Man Page yellow background, Ubuntu Mono 12, black text

**Note:** dvgs-lab3 went offline after session termination and did not recover. All subsequent testing done on dvgs-testmachine.

---

## 2026-05-01 — Desktop Session: Wallpaper, Thunderbird, Menu, Titlebar

### Wallpaper rotation: cron+feh → xfdesktop native

Replaced cron+feh wallpaper rotation with XFCE's built-in `xfdesktop` backdrop cycling. Key lesson: xfdesktop 4.18+ (Ubuntu 24.04) uses `backdrop-cycle-*` property names, not the older `image-show`/`image-period`. Monitor property must match xrandr output (e.g. `monitorHDMI-1`).

| File | Change |
|------|--------|
| `roles/desktop/templates/xfce4-desktop.xml.j2` | xfdesktop config with `backdrop-cycle-enable/period/random-order` |
| `roles/desktop/tasks/wallpaper.yml` | Deploy xfce4-desktop.xml, clean macOS `._*` files, remove legacy cron/feh |
| `roles/desktop/defaults/main.yml` | `desktop_wallpaper_interval_hours: 6` → `desktop_wallpaper_interval_minutes: 360` |
| `host_vars/dvgs-lab3.cttb` | `desktop_wallpaper_interval_minutes: 1` (testing) |

### Wallpaper refresh

Removed 12 old macOS defaults, added 22 Unsplash nature photos (35 total). Tarball rebuilt and uploaded to `pxe.cttb/ansible_assets/cttb-wallpapers.tar.gz` (216MB).

### Thunderbird email client

Ubuntu 24.04 `thunderbird` apt package is a snap wrapper (blocked on campus). Mozilla Team PPA also unreachable (`ppa.launchpad.net` blocked at network/firewall level). Solution: Mozilla tarball hosted on `pxe.cttb/ansible_assets/thunderbird-latest.tar.xz` (Thunderbird 150.0.1, 78MB).

| File | Change |
|------|--------|
| `roles/desktop/tasks/sw-thunderbird.yml` | **NEW** — removes snap, extracts tarball to `/opt/thunderbird/`, symlinks, deploys .desktop |
| `roles/desktop/tasks/sw.yml` | Added `include_tasks: sw-thunderbird.yml` |
| `roles/desktop/defaults/main.yml` | Added `thunderbird: true` |

For future PPA use: GPG key imported on debmirror, `mozillateam` entry in `host_vars/lxc-debmirror`, `launchpadcontent.net` added to e2guardian exceptions. Blocked until Launchpad IPs are allowed through srv-gw firewall.

### Custom applications menu

| File | Change |
|------|--------|
| `roles/desktop/templates/xfce-applications.menu.j2` | **NEW** — hostname+OS at top, category submenus, Sleep/Shut Down at bottom |
| `roles/desktop/templates/cttb-hostname.desktop.j2` | **NEW** — non-clickable menu label showing `hostname — Ubuntu version` |
| `roles/desktop/files/desktop-entries/cttb-sleep.desktop` | **NEW** — `xfce4-session-logout --suspend` (with confirmation) |
| `roles/desktop/files/desktop-entries/cttb-shutdown.desktop` | **NEW** — `xfce4-session-logout --halt` (with confirmation) |
| `roles/desktop/tasks/lookandfeel.yml` | Deploy tasks for menu, hostname entry, sleep/shutdown entries |

### System titlebar for all apps

| File | Change |
|------|--------|
| `roles/desktop/tasks/lookandfeel.yml` | `GTK_CSD=0`, `GTK_MODULES=appmenu-gtk-module`, `UBUNTU_MENUPROXY=1`, `MOZ_GTK_TITLEBAR_DECORATION=system` in `/etc/environment` |
| `roles/desktop/tasks/lookandfeel.yml` | Chrome policy `UseSystemTitleBar: true` via `/etc/opt/google/chrome/policies/managed/cttb-titlebar.json` |

### Other fixes

- Window title font → `Inter Display Bold 12` (was 10, too small for window controls)
- Global menu fixed: `GTK_MODULES=appmenu-gtk-module` was not set in environment
- Thunar icon symlinked to WhiteSur Finder-style `file-manager.svg`
- Lotus SVG icon added to repo with deploy task
- `systemd-timesyncd`: added `apt install` before enabling (was removed in prior session)
- `InterDisplay.tar.gz` uploaded to `pxe.cttb/ansible_assets/` (was 404)
- `pulseaudio.service` system-mode disabled + masked (24.04 uses per-user PipeWire)
- `systemd-networkd-wait-online.service` disabled (NM manages network, was hanging boot)
- `ansible_python_interpreter` fixed: `python3.13` → `python3` (host now on 24.04)
- SSH access: direct IP unreachable from Mac, requires `-J administrator@srv-nas.cttb` jump host

---

## 2026-05-01 — Terminal Font: SeriousShanns Nerd Font Mono

Switched terminal font from Ubuntu Mono to [Serious Shanns Nerd Font Mono](https://github.com/kaBeech/serious-shanns) — a legible monospace font with Nerd Font glyphs.

| File | Change |
|------|--------|
| `roles/desktop/files/config/terminalrc` | `FontName=SeriousShanns Nerd Font Mono 12` (was Ubuntu Mono 12) |
| `roles/desktop/tasks/lookandfeel.yml` | Added font install task — downloads `SeriousShannsNerdFontMono.tar.gz` from asset server to `/usr/share/fonts/opentype/serious-shanns/` |

Asset: `SeriousShannsNerdFontMono.tar.gz` (19MB, 6 OTF weights: Regular, Bold, Italic, BoldItalic, Light, LightItalic). Needs upload to `pxe.cttb/ansible_assets/`.

**Not yet tested** — dvgs-testmachine offline. Will verify after host is back online.

---

## 2026-05-02 — MediaWiki Migration: 1.29.1 → 1.43.1 LTS

Migrated `wiki.cttb` from a legacy container (Ubuntu 16.04, MW 1.29.1, Apache, PHP 7.0, MySQL 5.7) to a new container `wiki-2404` (Ubuntu 24.04, MW 1.43.1, nginx, PHP 8.3, MariaDB 10.11). Every component on the old wiki was years past end-of-life.

### Migration

| Step | Detail |
|------|--------|
| Container | `lxc launch ubuntu:24.04 wiki-2404` on srv-vm, IP 10.11.1.34 |
| DB dump | 17.3 MB in `mediawiki`-prefixed tables (125 pages, 1,456 revisions) |
| Stepping | MW 1.29 → 1.35 → 1.39 → 1.43, `maintenance/update.php` at each step |
| Images | Copied from old `/var/www/html/w/uploads/` to new `/var/www/html/w/images/` |
| DNS | dnsmasq entry updated: `00:16:3e:3c:bf:80,10.11.1.34,wiki` |
| Old container | Stopped, preserved as rollback |

### Stack Changes

| Component | Old | New |
|-----------|-----|-----|
| OS | Ubuntu 16.04 | Ubuntu 24.04 |
| MediaWiki | 1.29.1 | 1.43.1 LTS |
| Web server | Apache + mod_php | nginx + PHP 8.3-FPM |
| Database | MySQL 5.7 | MariaDB 10.11 |
| PHP | 7.0 | 8.3 |

### Configuration

- **nginx:** Short URLs (`/wiki/` → `/w/index.php`), `thumb.php` + `rest.php` routing, sensitive path blocking
- **VisualEditor:** Single edit tab with `$wgVisualEditorUseSingleEditTab = true`, `prefer-ve`
- **Skin:** Vector 2022 with City Lights dark theme (`/w/resources/assets/cttb-dark.css`)
- **Extensions:** ImageMap, Interwiki, WikiEditor, SyntaxHighlight_GeSHi, InputBox, ParserFunctions, CategoryTree, VisualEditor, MultimediaViewer, CodeEditor, Cite, CiteThisPage
- **SVG uploads** enabled with ImageMagick converter
- **Sitenotice:** Dismissable banner via `MediaWiki:Sitenotice` + `MediaWiki:Common.js` (localStorage)

### Content Updates

- Redesigned Main Page with categorized links to all 96 wiki pages and CTTB hero image
- Created **System Overview** page from infrastructure diagram (no credentials)
- Rewrote **IntroToLinux** with practical command-line guide
- Strengthened **IT Member Onboarding & Network Guide** with network overview, first-week checklist, services table
- Converted 18 pages from `<markdown>` tags to native wikitext (MarkdownExtraGeshiSyntax extension removed)
- Updated **ManagingMediawiki** ops log with migration entry

### Ansible

- New role: `roles/mediawiki` (nginx, PHP-FPM, MariaDB, MW install, migration tasks)
- Migration playbook: `plays/wiki-migrate.yml`
- Host vars: `host_vars/wiki-2404/` with encrypted vault (`wiki_vault.yml`)
- Dark theme CSS: `roles/mediawiki/files/cttb-dark.css`
- Wiki API tools: `.claude/wikitools/` (local only, not committed)

### Infrastructure Notes

- Container networking: static IP via `systemd-networkd` (netplan `udevadm` fails in LXC)
- MariaDB requires systemd sandbox override in LXC (`/etc/systemd/system/mariadb.service.d/lxc.conf`)
- No internet access from container — uses local apt mirror at `10.11.1.22` (apt.cttb)
- Tailscale subnet route `10.11.0.0/16` advertised from rui-desktop2 for remote access
- macOS SOCKS proxy (`localhost:1080`) requires `*.cttb` and `10.11.0.0/16` in bypass list

### Part of Sudhanix OS Initiative

This migration is part of the broader effort to modernize all CTTB hosts to Ubuntu 24.04 under the Sudhanix OS umbrella.

---

## 2026-05-02 — Wiki Content Overhaul

Comprehensive content pass across the entire wiki — new articles, enhancement of short pages, dead-end cleanup, and category consolidation.

### New Articles (7)

| Page | Content |
|------|---------|
| **NetworkBoot** | PXE pipeline architecture, boot sequence diagram, autoinstall profiles (desktop/server/minimal), TFTP file table, deployment commands, troubleshooting matrix |
| **Ssh** | Key management lifecycle (install-time + Ansible), sshd_config changes (IPv4-only), authorized_keys deployment, security notes |
| **Sudo** | Default Ubuntu policy, Ansible `become` usage, desktop panel/kiosk restrictions via sudo group, GTFOBins warnings, best practices |
| **Introduction to Shell Environments** | sh/bash/fish comparison with syntax tables, POSIX standard and GNU coreutils overview, SVG decision guide diagram, common gotchas table |
| **Introduction to Problem Solving** | Troubleshooting mindset (opens with Lao Tzu quote and shoshin/beginner's mind), man page anatomy and sections, `apropos`, GNU info pages, quick-ref tools (tldr, explainshell.com, cheat.sh, ArchWiki), technical literature formats, RFC reading guide with essential RFCs table, diagnostic tools (journalctl, dmesg, dig, nslookup, mtr, strace, lsof), troubleshooting checklist |
| **User:Jchandara** | User page — role, responsibilities, tools |
| **Template:Quotation** | Reusable blockquote with attribution — `{{quotation|text|author}}` |

### Page Enhancement (54 pages)

Enhanced the 54 shortest pages on the wiki. Each page received (preserving all original content):
- Inline `<ref>` footnotes with external sources
- `== See Also ==` sections with internal cross-links and external documentation URLs
- ASCII diagrams for complex topics (PKI hierarchy, rsyslog centralized logging, Nagios NRPE architecture, tcpdump workflow, udev rule pipeline)
- Wikitable command references (mdadm, rclone, tcpdump, VBoxManage, Nagios, NTP, unbound verbosity levels)
- Proper `[[Category:...]]` tags

### Dead-End Pages (77 → 0)

All 77 dead-end pages received See Also cross-links and category tags. Every page on the wiki now links to at least one other page.

### Category Consolidation (28 → 16)

| Action | Detail |
|--------|--------|
| **Merged** | IT Documentation → Documentation; IT Procedures + HowTo + Onboarding + Support Notes → Procedures; Networking + Network Administration → Network; Sound → Desktop; UPS + LXC → Infrastructure; USB Wifi Dongles → Network; Phones → Telephony |
| **Split** | Infrastructure → Servers (4 pages) + Backups (2 pages); Security → Physical Security (2 pages) |
| **Deleted** | 12 empty categories after consolidation |

Created description pages for all 16 remaining categories.

### Main Page Updates

Added to Getting Started: Introduction to Shell Environments, Introduction to Problem Solving. Updated sitenotice with Sudhanix OS mention and new content summary.

---

## 2026-05-03 — Storehouse: Internal File Server for Ansible Assets

### Motivation

The PXE server (`pxe.cttb`) has been accumulating non-boot assets — font tarballs, icon themes, ISOs, .deb packages, Thunderbird archives — alongside its TFTP/netinstall duties. This causes scope creep: the PXE host should handle boot and bootloader only. A dedicated file server keeps the PXE host focused and gives Ansible assets a permanent, purpose-built home.

### What was done

1. **Created LXC container** on srv-vm:
   ```
   lxc launch ubuntu:22.04 storehouse
   ```
   Attempted Debian 12 first but LXD 2.16 on srv-vm couldn't pull `images:debian/12`. Fell back to Ubuntu 22.04 (jammy) — proven on this host.

2. **New Ansible role** (`roles/storehouse/`):

   | File | Purpose |
   |------|---------|
   | `defaults/main.yml` | Copyparty version, paths, port, vault ref |
   | `tasks/main.yml` | System user, directory tree, copyparty download, systemd, ufw |
   | `handlers/main.yml` | Restart copyparty handler |
   | `templates/copyparty.service.j2` | Systemd unit with `CAP_NET_BIND_SERVICE` for port 80 |

   The role:
   - Creates `storehouse` system user/group
   - Creates `/srv/storehouse/ansible/isos/` directory tree
   - Downloads [copyparty](https://github.com/9001/copyparty) single-file Python HTTP server
   - Configures systemd service: anonymous read for all paths, write restricted to admin (vault credentials)
   - Opens UFW port 80

3. **Copyparty** chosen because: single Python file (no pip, no virtualenv), built-in directory browsing, upload support, ACL system, zero dependencies beyond Python 3.

4. **Inventory/vars updates:**
   - `inventory/hosts` — added `storehouse` to production containers
   - `group_vars/all` — `ansible_assets_url` now points to `http://storehouse.cttb/ansible` (updated in prior commit)
   - `host_vars/storehouse/main.yml` — vault password reference
   - `plays/storehouse.yml` — playbook with LXC setup instructions

### URL mapping

| Filesystem | URL |
|------------|-----|
| `/srv/storehouse/` | `http://storehouse.cttb/` |
| `/srv/storehouse/ansible/` | `http://storehouse.cttb/ansible` |
| `/srv/storehouse/ansible/isos/` | `http://storehouse.cttb/ansible/isos` |

### Migration plan

Existing assets on `pxe.cttb:/var/www/html/ansible_assets/` need to be copied to `storehouse.cttb:/srv/storehouse/ansible/`. Known assets:

| Asset | Size |
|-------|------|
| `cttb-wallpapers.tar.gz` | 216 MB |
| `InterDisplay.tar.gz` | 3.5 MB |
| `SeriousShannsNerdFontMono.tar.gz` | 19 MB |
| `thunderbird-latest.tar.xz` | 78 MB |
| `WhiteSur-gtk-theme.tar.gz` | 849 KB |
| `WhiteSur-icon-theme.tar.gz` | 6.6 MB |
| `WhiteSur-cursors.tar.gz` | 1.7 MB |

### Deployment

**Container provisioning** (manual, on srv-vm):
- `lxc launch ubuntu:22.04 storehouse` — no network attached by default on LXD 2.16
- `lxc config device add storehouse eth0 nic nictype=bridged parent=lxdbr0` — attach bridge
- Created `administrator` user with SSH key + NOPASSWD sudo
- Removed cloud-init apt proxy (`/etc/apt/apt.conf.d/80proxy`) that was routing through non-existent squid

**dnsmasq** (10.11.1.19):
- Added DHCP reservation: `00:16:3e:d9:57:cc,10.11.1.43,storehouse`
- DNS auto-created from DHCP hostname — `storehouse.cttb → 10.11.1.43`
- Verified: dnsmasq ✓, unbound ✓, SOCKS proxy ✓

**Ansible playbook** (`ANSIBLE_ROLES_PATH=./roles ansible-playbook plays/storehouse.yml -i inventory/hosts --become`):

| Run | ok | changed | failed | Issue |
|-----|-----|---------|--------|-------|
| 1 | 11 | 9 | 0 | All tasks passed, but copyparty crashed on start |
| 2 | 11 | 2 | 0 | Fixed volume syntax — service running, HTTP 200 |

**Fix:** Copyparty `-v` syntax uses one volume entry with combined permissions (`-v /path::r:rw,admin`), not two separate `-v` entries for the same path.

### Verification

```
$ curl -s -o /dev/null -w '%{http_code}' --socks5-hostname localhost:1080 http://storehouse.cttb/
200
$ curl -s -o /dev/null -w '%{http_code}' --socks5-hostname localhost:1080 http://storehouse.cttb/ansible/
200
```

### Remaining

- Add `vault_storehouse_admin_password` to `vars/jc_passwds.enc.yml` (admin password is set, vault entry pending)
- Copy remaining assets from `pxe.cttb:/var/www/html/ansible_assets/` to `storehouse.cttb:/srv/storehouse/ansible/`
- Remove `/var/www/html/ansible_assets/` from pxe.cttb after verification

---

## 2026-05-04 — Desktop-Distributed Assets Deployed to Storehouse

### What changed

Migrated WhiteSur theme assets from Ansible controller file copy to storehouse HTTP download.

**Previous approach:** `themes.yml` used `unarchive: src: <local-file>` and `copy: src: WhiteSur-icon-theme/` — transferring files from the Ansible controller over SSH to each target machine. The icon theme directory (65 MB uncompressed) was copied in full per machine.

**New approach:** Targets download assets from `storehouse.cttb/ansible/` via `get_url`. Assets are served once, fetched independently by each machine. No large file transfers from the controller.

### Assets uploaded to storehouse

| File | Size | Source |
|------|------|--------|
| `WhiteSur-Light.tar.xz` | 209 KB | `roles/desktop-distributed/files/WhiteSur-gtk-theme/release/` |
| `WhiteSur-Dark.tar.xz` | 201 KB | `roles/desktop-distributed/files/WhiteSur-gtk-theme/release/` |
| `WhiteSur-icon-theme.tar.gz` | 8.2 MB | Packaged from `roles/desktop-distributed/files/WhiteSur-icon-theme/` |

Icon theme tarball packed on storehouse (Linux) via rsync + tar to preserve symlinks — macOS `cp` cannot follow the broken relative symlinks in the `links/` subdirectory.

Tarball structure: `whitesur-icon-src/` root, matching the path `themes.yml` expects for `install.sh`.

### How to deploy assets to storehouse

For future assets (fonts, .deb packages, ISOs, tarballs):

```bash
# 1. SCP directly (for files you have locally)
scp /path/to/asset.tar.gz administrator@10.11.1.43:/srv/storehouse/ansible/
# Fix ownership after:
ssh administrator@10.11.1.43 "sudo chown storehouse:storehouse /srv/storehouse/ansible/asset.tar.gz"

# 2. For large dirs with symlinks — rsync to Linux first, then tar on target:
rsync -a --links /local/dir/ administrator@10.11.1.43:/tmp/staging-dir/
ssh administrator@10.11.1.43 "tar czf /srv/storehouse/ansible/asset.tar.gz -C /tmp staging-dir && rm -rf /tmp/staging-dir"
ssh administrator@10.11.1.43 "sudo chown storehouse:storehouse /srv/storehouse/ansible/asset.tar.gz"

# 3. Verify via SOCKS proxy
curl -s -o /dev/null -w '%{http_code}' http://storehouse.cttb/ansible/asset.tar.gz
```

### Ansible changes

| File | Change |
|------|--------|
| `roles/desktop-distributed/tasks/themes.yml` | Replaced local `copy`/`unarchive` with `get_url` + `remote_src: yes` unarchive |
| `plays/desktop-distributed.yml` | **NEW** — playbook with per-site theme vars (DVGS/DVBS/DRBU), usage examples |

### Verification

```
$ curl -s -o /dev/null -w '%{http_code}' http://storehouse.cttb/ansible/WhiteSur-Light.tar.xz
200
$ curl -s -o /dev/null -w '%{http_code}' http://storehouse.cttb/ansible/WhiteSur-Dark.tar.xz
200
$ curl -s -o /dev/null -w '%{http_code}' http://storehouse.cttb/ansible/WhiteSur-icon-theme.tar.gz
200
```

---

## 2026-05-04 — Storehouse Homepage & h5ai File Browser

### What changed

Completed the storehouse.cttb web interface: a citylights-themed landing page and a working h5ai file browser scoped to `/ansible/`.

### Homepage (`/`)

- Citylights dark theme (self-hosted CSS + fonts — no external CDN except h5ai's own LXGW load)
- Sriracha font deployed locally via `fonts.css` with absolute paths (`/fonts/...`)
- `p31m-pattern.svg` added to role files (was missing, caused 404s in citylights CSS)
- **Tagline:** "Internal File Server — City of Ten Thousand Buddhas" (changed from Ansible-specific wording)
- **Message fieldset** (☸ Message): eighth consciousness pun — ālayavijñāna as storehouse mind
- **Assets fieldset:** icon grid linking into `/ansible/`
- Click-to-copy on all `<code>` elements in quick reference

### h5ai file browser (`/ansible/`)

**Root cause of empty listing:** The manti-X fork of h5ai (v0.33.0) removed the `_h5ai/` wrapper directory present in the original. h5ai's `class-setup.php` computes `ROOT_PATH` by going up N `dirname()` levels from `class-setup.php` — the original assumed `_h5ai/private/php/core/`, but manti-X uses `private/php/core/`. This made `ROOT_PATH` resolve to `/srv/` (parent of the web root) instead of `/srv/storehouse/`, so h5ai was scanning `/srv/ansible/` (nonexistent) instead of `/srv/storehouse/ansible/`.

**Fix:** Patched `ROOT_PATH` computation in `class-setup.php` to not go up the extra level:
```php
// Before (broken for manti-X):
$this->set('ROOT_PATH', Util::normalize_path(dirname($this->get('H5AI_PATH')), false));
// After:
$this->set('ROOT_PATH', Util::normalize_path($this->get('H5AI_PATH'), false));
```
Patch applied idempotently via Ansible `replace` task in `roles/storehouse/tasks/main.yml`.

**Hidden patterns:** Added `^storehouse` to h5ai's `hidden` array to suppress the server root directory name appearing as a ghost entry in the sidebar.

**PHP ownership:** Set `private/` and `public/` to `www-data:www-data` so PHP-FPM can write the cache.

### Ansible changes

| File | Change |
|------|--------|
| `roles/storehouse/files/index.html` | New homepage: citylights theme, ālaya pun, asset grid |
| `roles/storehouse/files/fonts.css` | Absolute font paths (`/fonts/...`) |
| `roles/storehouse/files/p31m-pattern.svg` | Added missing citylights background pattern |
| `roles/storehouse/tasks/main.yml` | h5ai ownership, ROOT_PATH patch, hidden config, p31m-pattern deploy |
| `roles/storehouse/templates/storehouse-nginx.conf.j2` | Added `/index.html` exact-match location |
| `inventory/hosts` | Default inventory changed from `hosts_os_upgrade.ini` → `hosts` |
| `inventory/host_vars/storehouse/main.yml` | Added `ansible_python_interpreter` to suppress discovery warning |
| `ansible.cfg` | Added `./roles` to `roles_path`; changed default inventory to `./inventory/hosts` |
| `plays/deploy-assets.yml` | Added wallpapers asset group |

### deploy-assets.yml

Assets now deployed via playbook (not manual SCP). Run:
```bash
ansible-playbook plays/deploy-assets.yml -i inventory/hosts --become
# or per-group:
ansible-playbook plays/deploy-assets.yml --tags themes
ansible-playbook plays/deploy-assets.yml --tags wallpapers
```

### Wiki sidebar

Added `storehouse.cttb` to `MediaWiki:Sidebar` under Other Services alongside PXE, APT, and Git.

### Browser proxy note

Zen browser requires **"Auto-detect proxy settings for this network"** to reach `.cttb` hosts via the SOCKS tunnel. "Use system proxy settings" and manual SOCKS5 both fail due to a Firefox/Zen CFNetwork relay issue.
