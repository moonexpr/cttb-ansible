# Update Journal: Ubuntu 24.04 Upgrade

**Branch:** feature/ubuntu22-upgrade
**Started:** 2026-04-16
**Test machine:** dvgs-testmachine.cttb (formerly dvgs-lab3, IP: 10.11.9.23)

> **See also:** [DEPLOYMENT.md](DEPLOYMENT.md) — full deployment pipeline & commands | [GitHub milestones](https://github.com/moonexpr/cttb-ansible/milestones) — forward-looking work (BACKLOG.md migrated 2026-05-07)

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
5. **Hardened server access** — changed `jc` password to `a` on pxe.cttb and dnsmasq.cttb. Added `Match User jc` / `PasswordAuthentication no` to sshd_config on both servers. rui-desktop2 skipped at the time (now has sudo).
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
2. rui-desktop2 → `johnchandara` account → has sudo access. Can see `/home/kit.chong`.
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

---

## 2026-05-04 — Desktop UX Backlog Completion

Completed all items from the May 4th upgrade backlog. Machine: dvgs-testmachine.cttb (10.11.30.60).

### Changes

| Task | Solution | Files |
|------|----------|-------|
| Terminal font 10pt | Changed SeriousShanns from 12→10 in terminalrc | `files/config/terminalrc` |
| Window snapping | Already done (`snap_to_border/windows: true` in xfwm4.xml.j2) | — |
| Center window spawn | Already done (`placement_mode: center` in xfwm4.xml.j2) | — |
| Log Out menu entry | Created `cttb-signoff.desktop`, added to menu layout before Sleep/Shutdown | `files/desktop-entries/cttb-signoff.desktop`, `templates/xfce-applications.menu.j2`, `tasks/lookandfeel.yml` |
| Thunar list view | Created `thunar.xml.j2` with `ThunarDetailsView` default | `templates/thunar.xml.j2`, `tasks/ux.yml` |
| Meta key → app menu | Created `xfce4-keyboard-shortcuts.xml.j2` with Super_L binding + window tiling shortcuts | `templates/xfce4-keyboard-shortcuts.xml.j2`, `tasks/ux.yml` |
| Zen Browser | Flatpak install from Flathub, new `zen_browser` variable | `tasks/sw-browser.yml`, `defaults/main.yml` |
| Chrome default browser | `xdg-settings set default-web-browser` after Chrome install | `tasks/sw-browser.yml` |
| Dark theme icons | Switched `icon_theme` from `WhiteSur` to `WhiteSur-dark` | `defaults/main.yml`, `tasks/lookandfeel.yml` |
| Thunderbird proxy | Deploy `cttb-proxy.js` autoconfig to `/opt/thunderbird/defaults/pref/` | `tasks/sw-thunderbird.yml` |
| App search (Spotlight) | `xfce4-appfinder` package + Super+Space shortcut | `tasks/lubuntu.yml`, `templates/xfce4-keyboard-shortcuts.xml.j2` |
| Greeter wallpaper | Point lightdm-gtk-greeter background to wallpaper rotation dir (random on each login) | `templates/lightdm-gtk-greeter.j2`, `tasks/lookandfeel.yml` |
| System sounds | Enabled `EnableEventSounds` in xsettings, installed `libcanberra-gtk3-module` + `sound-theme-freedesktop` | `templates/xsettings.xml.j2`, `tasks/sound.yml` |
| Fonts to storehouse | Already done — all assets use `ansible_assets_url` (storehouse) | — |
| Wallpaper archive | Rebuilt `cttb-wallpapers.tar.gz` (208MB) and uploaded to storehouse | storehouse:/srv/storehouse/ansible/ |
| Panel in Plank dock | Deployed `devilspie2` with Lua rule to set `skip_tasklist` on xfce4-panel wrappers | `files/config/devilspie2/panel-skip-taskbar.lua`, `tasks/ux.yml`, `tasks/lubuntu.yml` |

### New files

- `roles/desktop/tasks/ux.yml` — Desktop UX tasks (keyboard shortcuts, Thunar, devilspie2)
- `roles/desktop/templates/thunar.xml.j2` — Thunar xfconf defaults
- `roles/desktop/templates/xfce4-keyboard-shortcuts.xml.j2` — XFCE keyboard shortcuts
- `roles/desktop/files/desktop-entries/cttb-signoff.desktop` — Log Out menu entry
- `roles/desktop/files/config/devilspie2/panel-skip-taskbar.lua` — Hide panel from Plank
- `plays/util-screenshot.yml` — Remote screenshot utility for debugging

### Architecture notes

**ux.yml task file** — Extracted keyboard shortcuts and Thunar config from `lookandfeel.yml` into a dedicated `tasks/ux.yml` file, included from `setup/default.yml`. This separates UX behavior (shortcuts, window rules) from visual theming (fonts, icons, panel layout).

**devilspie2** — Lightweight Lua-scripted window matching daemon. Runs as autostart for all users. Rules in `/etc/xdg/devilspie2/`. Can be extended with additional `.lua` files to control window behavior (always-on-top, workspace assignment, geometry, skip-taskbar). Useful for kiosk-like environments where window behavior needs to be enforced system-wide.

**Thunderbird proxy** — Campus machines use HTTP proxy at `10.11.1.1:8080` (e2guardian → squid). Thunderbird's `defaults/pref/cttb-proxy.js` sets `network.proxy.type=1` (manual) with the campus proxy and bypass for `.cttb`/`10.11.0.0/16`. This runs at install time — existing user profiles are not affected (users would need to reset Thunderbird's proxy settings manually or delete their profile).

### Remote access notes

- dvgs-testmachine actual IP: `10.11.30.60` (not 10.11.9.23 from old inventory)
- Direct SSH works: `ssh administrator@10.11.30.60`
- Storehouse direct SSH: `ssh -o ProxyJump=none administrator@10.11.1.43`
- ProxyJump via `cttb` Tailscale node (100.121.41.88) fails — key not authorized for `johnchandara`

---

## 2026-05-04 — Infrastructure Fixes & Desktop Polish

### Wiki DNS Resolution Fixed
- **Problem:** `wiki.cttb` was resolving to an old IP (10.11.1.31) or dynamic IP (10.11.13.133) due to a name conflict with the legacy container and stale static records.
- **Fixes:**
    - Stopped legacy `wiki` container on `srv-vm`.
    - Updated `/etc/unbound/unbound.conf.d/cttb` on `ub-adult` and `ub-igdvs` to point to `10.11.1.34`.
    - Flushed Unbound zone cache (`unbound-control flush_zone cttb.`).
    - Resolved `dnsmasq` conflict on `10.11.1.19` by removing stale `lxc-cm` entry and adding `host-record` for `wiki.cttb`.
- **Verification:** DNS now correctly resolves to `10.11.1.34` across all resolvers.

### SSH & Proxy Access
- **Problem:** SSH ProxyJump to `rui-desktop2` (for SOCKS tunnel) failed due to unauthorized key and passphrase prompts.
- **Fixes:**
    - Authorized `jc@cosmicbook` ECDSA key on `rui-desktop2` for `johnchandara` user.
    - Loaded passphrase-protected key into local `ssh-agent`.
    - Updated `~/.local/bin/cttb-proxy` to use direct LAN IP (`10.11.24.24`) as jump host for better reliability.
- **Result:** SOCKS tunnel stable; `wiki.cttb` and `pxe.cttb` fully accessible via browser.

### Desktop Assets Updated
- **Icon Theme:** Rebuilt `WhiteSur-icon-theme` on `storehouse` to include `WhiteSur-dark` variant. Repackaged and deployed to `http://storehouse.cttb/ansible/`.
- **Sound Theme:** Integrated `bigsur` sound theme.
    - Downloaded and hosted `macos-bigsur-sound-theme.tar.gz` on `storehouse`.
    - Updated `desktop` role (`defaults/main.yml`, `tasks/sound.yml`) to install and enable the theme.
    - `xsettings.xml.j2` now correctly applies `SoundThemeName=bigsur`.

---

## 2026-05-04 — Deployment Fixes & Greeter Styling

### Chrome Install & NFS Lock Fix
- **Problem:** Chrome was never installed via apt — only the signing key and repo were added. The `.desktop` file was also referenced as `google-chrome-stable.desktop` but the package installs `google-chrome.desktop`.
- **Fix:** Added `apt: name=google-chrome-stable` task in `sw-browser.yml`, corrected `.desktop` filename, guarded replace + xdg-settings with architecture check (amd64 only).
- **Problem:** Chrome profile locked by stale NFS `SingletonLock` symlink from another machine (dvgs-lab3). Students with NFS homes will hit this whenever Chrome crashes or a machine reboots uncleanly.
- **Fix:** Created `/usr/local/bin/clean-chrome-locks.sh` — on login, checks if the lock symlink points to a different hostname and removes it. Deployed as `/etc/xdg/autostart/clean-chrome-locks.desktop`.

### Log Out Menu Duplicate
- **Problem:** "Log Out" appeared twice in the app menu — once in the alphabetical category list and once at the bottom. The system `xfce4-session-logout.desktop` has `X-Xfce-Toplevel` category and showed up via `<Merge type="all"/>` in addition to our custom `cttb-signoff.desktop` in the Layout.
- **Fix:** Added `<Exclude><Filename>xfce4-session-logout.desktop</Filename></Exclude>` at the top level of `xfce-applications.menu.j2`.

### 24-Hour Clock
- Changed panel clock format from `%l:%M %p` (12hr) to `%H:%M` (24hr) in `xfce4-panel.xml.j2`.

### VSCode Repo Conflict
- **Problem:** VSCode package auto-creates `vscode.sources` (deb822 format) with `microsoft.gpg`, conflicting with our `vscode.list` using `microsoft.asc`. Broke all apt operations.
- **Fix:** Added tasks in `sw-vscode.yml` to remove `vscode.sources` and stale `microsoft.gpg` after install.

### LightDM Greeter Improvements
- **Wallpaper:** Greeter `background` now points to a specific file (`{{desktop_wallpaper_dir}}/{{desktop_login_background}}`) — lightdm-gtk-greeter doesn't support directory paths (was black screen).
- **Default wallpaper:** Changed `pic_bg` from `bg-windos10.jpg` (missing) to `Big-Sur-Day.jpg`.
- **Language indicator:** Removed `~language` from greeter indicators — was showing raw "[language_code]" text.
- **Theme:** Added `theme-name = WhiteSur-Dark` to greeter conf.
- **macOS-style CSS:** Created `config/lightdm-gtk-greeter.css` with dark semi-transparent login box, rounded corners, styled input fields, and blue accent buttons. Loaded via `@import` in WhiteSur-Dark's `gtk.css`.

### Files Changed

| File | Change |
|------|--------|
| `tasks/sw-browser.yml` | Added Chrome apt install, fixed .desktop name, arch guards |
| `tasks/sw-vscode.yml` | Added repo/key conflict cleanup tasks |
| `tasks/ux.yml` | Added Chrome NFS lock cleanup script + autostart |
| `tasks/lookandfeel.yml` | Added greeter CSS deploy + theme import task |
| `templates/xfce-applications.menu.j2` | Excluded system logout entry |
| `templates/xfce4-panel.xml.j2` | 24hr clock format |
| `templates/lightdm-gtk-greeter.j2` | Added theme-name, fixed wallpaper path, removed ~language |
| `files/config/lightdm-gtk-greeter.css` | NEW — macOS-style greeter login box |
| `files/config/clean-chrome-locks.sh` | NEW — NFS Chrome lock cleanup |
| `defaults/main.yml` | Changed pic_bg to Big-Sur-Day.jpg |
| `PROJECT.md` | Added incremental testing docs, expanded role reference |

### Deployment Status
- **ok=134, changed=10, failed=1** (Zoom signature only — pre-existing, skip with `--skip-tags zoom`)
- Chrome, Firefox, Zen Browser, Thunderbird, VSCode all installed and working
- Greeter: Big Sur wallpaper, WhiteSur-Dark theme, macOS-style CSS, 24hr clock
- Desktop: Chrome launches with system titlebar, NFS lock cleanup active

## 2026-05-04 — Backlog Audit & Verification

Five parallel verification tasks run against dvgs-testmachine.

### Completed

| Task | Result |
|------|--------|
| **srv-gw filter revert** | Removed stale `10.11.9.23` from adult e2guardian group in `host_vars/srv-gw`. Set ips to `[]`. |
| **Wallpaper verification** | Big-Sur-Day.jpg present (10.8MB), 35 wallpapers total, tarball on storehouse (HTTP 200). |
| **Unified wallpaper** | Changed all group_vars (dvgs, dvbs, drbu) to `pic_bg: Big-Sur-Day.jpg`. Removed per-school overrides. |

### Diagnosed (needs further action)

| Task | Finding |
|------|---------|
| **LDAP auth** | TLS/STARTTLS handshake failing. nscd running but `do_start_tls failed` in logs. LDAP server at ldap.cttb (10.11.1.25) reachable on port 389, port 636 (LDAPS) refused. PAM/NSS config is correct. 439 local users resolve, 0 LDAP. Fix needs LDAP server TLS config or disabling TLS in client config. |
| **Zoom .deb** | Storehouse copy corrupted — 4.3KB HTML error page, not a .deb. Zoom 7.0.0.1666 currently installed. Fresh download from zoom.us succeeded (281MB valid .deb at `/tmp/zoom_new.deb`). Upload to storehouse needed. |
| **devilspie2** | Not starting on login. XFCE session + Plank running, but devilspie2 absent from process list. Remote screenshot shows black desktop. Need to check autostart config and Lua script syntax. |

---

## 2026-05-05 — Plank Dock Apps & App Finder Config Pulled from Test Machine

### What was done

Pulled two user-modified configs from dvgs-testmachine.cttb (10.11.30.60) and codified them in the Ansible role.

### 1. Plank dock launchers

Pulled from `/home/administrator/.config/plank/dock1/launchers/`. These define the apps pinned to the bottom dock for all new users.

**Dock order:** Chrome, Zoom, LibreOffice Writer, Calculator, App Finder, Thunar, gedit, Thunderbird, GIMP, LibreOffice Calc

**Files created:** `roles/desktop/files/config/etc-skel/.config/plank/dock1/launchers/` — 10 `.dockitem` files. Deployed to `/etc/skel/` via the existing `setup default account files` task in `lookandfeel.yml`.

### 2. xfce4-appfinder config

Pulled from user's xfconf on dvgs-testmachine. Settings:

| Property | Value | Effect |
|----------|-------|--------|
| `icon-view` | true | Grid of app icons (not list) |
| `hide-category-pane` | true | No sidebar categories — cleaner launcher |
| `always-center` | true | Opens centered on screen |
| `sort-by-frecency` | true | Frequently-used apps rise to top |
| `item-icon-size` | 4 | Larger icons in grid |

**Files created:** `roles/desktop/templates/xfce4-appfinder.xml.j2`
**Task added:** `roles/desktop/tasks/ux.yml` — deploys to `/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-appfinder.xml`

### Note

Plank launchers go to `/etc/skel/` — only affects **new** user accounts. Existing users keep their current dock. The appfinder config goes to `/etc/xdg/` — system default, overridden by per-user xfconf.

---

## 2026-05-05 — Sudhanix OS 26 Branding

### What was done

Rebranded the OS identity. `lsb_release -a` and `/etc/os-release` now report Sudhanix 26 instead of Ubuntu 24.04. MOTD on SSH/console login points users to wiki.cttb as primary documentation.

| Field | Value |
|-------|-------|
| Distributor ID | sudhanix |
| Description | Sudhanix 26 |
| Release | 26 |
| Codename | storehouse |

### Files

| File | Purpose |
|------|---------|
| `roles/common/templates/lsb-release.j2` | `/etc/lsb-release` — read by `lsb_release` command |
| `roles/common/templates/os-release.j2` | `/etc/os-release` — read by systemd, gnome-info, login banners. `ID_LIKE=ubuntu` keeps tooling that probes for ubuntu happy. `UBUNTU_CODENAME` retained from `ansible_distribution_release` for compat. |
| `roles/common/templates/motd-header.j2` | Replacement `/etc/update-motd.d/00-header` — points to wiki.cttb (primary), help.ubuntu.com + docs.xfce.org (secondary) |
| `roles/common/defaults/main.yml` | Added `sudhanix_*` brand vars |
| `roles/common/tasks/setup/default.yml` | 4 new tasks: deploy lsb-release, os-release, motd-header; disable Ubuntu's `10-help-text`, `50-motd-news`, `90-updates-available`, `91-release-upgrade`, `95-hwe-eol` (chmod -x) |

Tag: `sudhanix_branding` (also `motd` for the welcome message tasks).

### Caveats

- `/etc/os-release` is owned by the `base-files` package. Any apt upgrade of `base-files` will overwrite our template. dpkg-divert would be more robust; for now, re-running the role after upgrades is the recovery path.
- `lsb_release -a` reads from `/etc/lsb-release` first, but on some 24.04 builds it falls back to `/usr/share/distro-info/ubuntu.csv` for codename mapping. Test on first deploy.
- The disabled MOTD scripts use `chmod 0644` (drop +x) rather than deletion — survives apt reinstalls without leaving empty files.

### Strategic note: Do we make our own distro?

**Decision: No fork. Brand and configure, don't fork.** Sudhanix OS is a brand + Ansible profile + `apt.cttb` debmirror layered on Ubuntu noble. The benefits we want (VM testing, greater control, identity) don't require a fork — Ansible + autoinstall already deliver them. The cost of a true fork (CVE patching, ABI curation, installer engineering, signing infra) is enormous and hidden, with no upside for CTTB at current scale. Revisit only when we ship 10+ packages we build ourselves or hit an Ubuntu requirement we can't meet.

Path forward if more brand cohesion is wanted: Plymouth splash, GRUB theme, custom ISO via cubic/livecd-rootfs (pre-applies Ansible role at ISO build time, ~2 days of work). PXE pipeline + autoinstall already gives us most of this; an installer ISO would just be the same artifact, packaged for offline use.

---

## 2026-05-05 — Sudhanix Branding: Must-Fix Tasks + Role Rename

### Must-Fix branding (codified in `roles/common`)

| Item | Mechanism |
|------|-----------|
| `os-release` survives `base-files` upgrades | `dpkg-divert --local --rename --add /etc/os-release` (also for `lsb-release`). Idempotent via `creates: /etc/os-release.distrib`. |
| GRUB menu shows "Sudhanix" | `DISTRIB_ID=Sudhanix` (capitalized) — existing `/etc/default/grub` already uses `\`lsb_release -i -s\`` for `GRUB_DISTRIBUTOR`. lsb-release task notifies `update grub` handler. |
| GRUB theme | Scaffolded; gated by `sudhanix_grub_theme_enabled: false`. Asset URL: `{{ ansible_assets_url }}/sudhanix-grub-theme.tar.gz`. Sets `GRUB_THEME=` in `/etc/default/grub`. |
| Plymouth splash | Scaffolded; gated by `sudhanix_plymouth_theme_enabled: false`. Asset URL: `{{ ansible_assets_url }}/sudhanix-plymouth.tar.gz`. Uses `update-alternatives --set default.plymouth ...` and notifies `update initramfs`. |
| `/etc/issue` + `/etc/issue.net` | New templates; show `Sudhanix 26 \n \l` at TTY/SSH login banner. |
| `/etc/legal` | Replaced Ubuntu's notice with one-line Sudhanix-derived text. |

New handlers in `roles/common/handlers/main.yml`: `update grub`, `update initramfs` (both gated to skip in LXC).

All branding tasks tagged `sudhanix_branding`. GRUB-theme + Plymouth subtags: `grub_theme`, `plymouth`.

### Role rename

| Old | New |
|-----|-----|
| `roles/desktop/` | `roles/sudhanix-core/` |
| `roles/desktop-distributed/` | `roles/sudhanix-distributed/` |
| `roles/sudhanix-core/tasks/ux.yml` | `roles/sudhanix-core/tasks/sudhanix-ux.yml` |
| `plays/desktop-distributed.yml` | `plays/sudhanix-distributed.yml` |
| Tag `desktop` | Tag `sudhanix-core` |
| Tag `ux` | Tag `sudhanix-ux` |

Updated all `- desktop` / `- ux` tag entries in renamed role's tasks; updated `role: desktop-distributed` → `role: sudhanix-distributed` in plays; updated `include_tasks: ux.yml` → `include_tasks: sudhanix-ux.yml`. README + var-file headers refreshed. Historical UPDATE_JOURNAL paths left untouched (record of what was true at the time).

### Caveats

- `git mv` of `desktop-distributed/` was blocked by a deleted-but-unstaged wallpaper (`robert-lukeman-_RBcxo9AU-U-unsplash.jpg`). Worked around with `mv` + `git add -A`; rename detection picked up 30,857 of the WhiteSur theme files as renames. Verify with `git status -s | awk '{print $1}' | sort | uniq -c`.
- The Plymouth task uses `update-alternatives --set` with `changed_when: false` because `--set` is non-idempotent in its output; the actual change-tracking comes from the unarchive task notifying `update initramfs`.
- Deploying GRUB theme + Plymouth requires the asset tarballs on storehouse first. Until then, leave the `*_enabled` flags `false` (default).

---

## 2026-05-05 — Sudhanix Branding Deployed to dvgs-testmachine

### Pre-deploy fixes

| Issue | Fix |
|-------|-----|
| `utils/setup-env` pointed at `${ANSIBLE_BASE}/hosts` (nonexistent) | Updated to `${ANSIBLE_BASE}/inventory/hosts` |
| `--tags sudhanix_branding` matched 0 tasks | Changed `roles/common/tasks/main.yml` from `include_tasks` to `import_tasks` for `setup/default.yml`. Static import lets `--list-tasks` and tag filtering see nested tags. Platform-specific include kept as `include_tasks` (uses `first_found` + `skip:true`, which requires dynamic). |
| `roles/sudhanix-distributed/meta/main.yml` depended on `common-20.04` (renamed/removed) | Changed to `- { role: common }`. This was a pre-existing breakage exposed by the syntax check. |

### Deploy

```
ansible-playbook plays/cs-lab-2404.yml -l dvgs-testmachine \
    --tags sudhanix_branding --diff --become
```

Result: `ok=11 changed=10 unreachable=0 failed=0 skipped=6 ignored=1`

The 1 ignored failure is `file` module on absent MOTD scripts (`90-updates-available`, `95-hwe-eol`) — Ubuntu 24.04 doesn't ship all five. `ignore_errors: yes` handles it.

### Verified post-deploy on dvgs-testmachine

| Check | Result |
|-------|--------|
| `lsb_release -a` | `Distributor ID: Sudhanix`, `Description: Sudhanix 26`, `Release: 26`, `Codename: storehouse` ✓ |
| `/etc/os-release` | `PRETTY_NAME="Sudhanix 26"`, `ID=sudhanix`, `ID_LIKE=ubuntu`, `HOME_URL="http://wiki.cttb/"` ✓ |
| `/etc/issue` | `Sudhanix 26 \n \l` ✓ |
| MOTD `/etc/update-motd.d/00-header` | Wiki.cttb primary, Ubuntu/XFCE secondary ✓ |
| `/etc/legal` | Sudhanix-derived notice ✓ |
| `dpkg-divert --list` | Both `/etc/lsb-release` and `/etc/os-release` diverted to `.distrib` ✓ |
| GRUB menu strings | `menuentry 'Sudhanix GNU/Linux'` ✓ (was 'Ubuntu GNU/Linux') |

### Known follow-ups

- `roles/sudhanix-distributed/tasks/main.yml` still has bare `include:` (removed in ansible-core 2.20+). Fix when `sudhanix-distributed` play is next exercised.
- `--tags sudhanix-ux` (and other tags inside `sudhanix-core`) still don't show in `--list-tasks` because `sudhanix-core/tasks/main.yml` uses `include_tasks` for `setup/default.yml`. Same fix as `common` would resolve it; deferred until needed.

---

## 2026-05-05 — Sudhanix Plymouth Boot Splash

### Generated artwork

Used FLUX.1 Krea-Dev (HuggingFace) to generate a high-quality bitmap render of a white lotus on pure black background — symmetrical, glowing edges, photographic studio render. Two prior attempts had spurious objects (Apple logo, hiking boot — model interpreting "boot logo aesthetic" too literally). Final prompt avoided trigger words: "Symmetrical white lotus flower, fully bloomed, viewed from directly above, twelve smooth pointed petals... soft glowing white silhouette on solid pure black background... ethereal serene mood, empty smooth flower center with no objects". Seed 89081076, 1024×1024 → resized to 800×800 PNG.

### Theme structure

`roles/sudhanix-core/files/plymouth/sudhanix/`:

| File | Purpose |
|------|---------|
| `sudhanix.plymouth` | Theme metadata; `ModuleName=script` |
| `sudhanix.script` | Plymouth script: black background, centered logo at 22% screen height, thin progress bar 6% below, password prompt + message handlers |
| `lotus.png` | 800×800 lotus bitmap (FLUX render) |
| `progress-bg.png` | 240×4 px, white at 25% alpha — progress bar track |
| `progress-fill.png` | 240×4 px, opaque white — progress bar fill, cropped by `boot_progress_cb` |

### Asset deployment

- Tarball packaged via `tar czf sudhanix-plymouth.tar.gz sudhanix/` (260 KB)
- Uploaded to `storehouse.cttb:/srv/storehouse/ansible/sudhanix-plymouth.tar.gz` (HTTP 200)
- New `plumouth` tag block added to `plays/deploy-assets.yml` for future rebuilds: rsync source → tar → place

### Ansible task fix

The original `update-alternatives --set` task failed (`alternative not registered`). Split into two tasks:

1. `register Sudhanix Plymouth theme as alternative` — `update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth /usr/share/plymouth/themes/sudhanix/sudhanix.plymouth 100`
2. `select Sudhanix Plymouth theme via update-alternatives` — `update-alternatives --set ...`

### Verified post-deploy on dvgs-testmachine

| Check | Result |
|-------|--------|
| Theme files at `/usr/share/plymouth/themes/sudhanix/` | All 5 files present ✓ |
| `/etc/alternatives/default.plymouth` symlink | → `/usr/share/plymouth/themes/sudhanix/sudhanix.plymouth` ✓ |
| `apt install plymouth-themes` | Pulled in `plymouth-label` + `plymouth-theme-spinner` deps |
| `update-initramfs -u` | Generated `/boot/initrd.img-6.8.0-111-generic` with new theme baked in |

### Visual verification

Plymouth runs at boot only — requires reboot of dvgs-testmachine to observe. Default `sudhanix_plymouth_theme_enabled: true` now in `roles/common/defaults/main.yml`. Re-running `cs-lab-2404.yml` with `--tags plymouth` is idempotent.

### Caveats

- The `update-initramfs` handler doesn't fire on idempotent re-runs (since `--install`/`--set` are `changed_when: false`). On the **first** deploy, run an explicit `ansible <host> -b -m command -a "update-initramfs -u"` to bake the theme. Subsequent deploys only need this if the source PNG changes.
- Plymouth writes raw RGBA frames straight to KMS — only visible on the actual console at boot. Cannot be previewed over SSH.

---

## 2026-05-05 — End of Session Wrap-up

### What shipped today

1. **Plank dock launchers + xfce4-appfinder template** — pulled from `dvgs-testmachine` user mods, codified into `roles/sudhanix-core/files/config/etc-skel/` and a new system-wide appfinder XML.
2. **Sudhanix OS 26 branding** — `lsb-release`, `os-release`, `motd-header`, `issue`, `issue.net`, `legal` templates; `dpkg-divert` for upgrade survival; `update-grub` and `update-initramfs` handlers; `import_tasks` fix in `common/tasks/main.yml` so tag filtering works through the role.
3. **Role rename** — `desktop` → `sudhanix-core`, `desktop-distributed` → `sudhanix-distributed`, `ux.yml` → `sudhanix-ux.yml`. 15 plays + 5 task files + meta dep updated. Tags `desktop`/`ux` → `sudhanix-core`/`sudhanix-ux`.
4. **Plymouth boot splash** — FLUX-rendered lotus on black, macOS-style script with progress bar, registered + selected via `update-alternatives`, baked into initrd.
5. **Utils fix** — `setup-env` now points at `inventory/hosts` (was nonexistent `hosts` at repo root).

### Outstanding

- `roles/sudhanix-distributed/tasks/main.yml` still uses bare `include:` (deprecated in ansible-core 2.20). Fix when next exercising that play.
- GRUB theme assets not yet built (gated `sudhanix_grub_theme_enabled: false`).
- Must reboot `dvgs-testmachine` to visually verify Plymouth splash.
- Wiki docs for Sudhanix 26 release (user + sysadmin) — next session.

---

## 2026-05-05 — Wiki Drafts + Backlog + Final Test Deploy

### Wiki article drafts (not yet published)

Drafted two wiki pages locally and saved to `.claude/wiki-pages/`:

- `Sudhanix.txt` (~7.8 KB) — user-facing introduction. Sudhana's namesake, quick tour, keyboard shortcuts, getting help, what differs from stock Ubuntu
- `IT_Sudhanix.txt` (~17 KB) — sysadmin reference. Architecture overview, identity/branding mechanics, role catalog, asset pipeline, deploy commands, customization vars, troubleshooting recipes

Both gitignored under `.claude/`. Ready to publish via `wiki-edit.sh "Sudhanix" .claude/wiki-pages/Sudhanix.txt` etc.

### Backlog: 12 future wiki articles

Added "Wiki Documentation (before mass upgrade)" section to BACKLOG.md. Six critical sysadmin pages (Upgrade Procedure, Pre-Upgrade Checklist, Rollback Plan, Verification Checklist, Per-Site Customization, Asset Manifest), three user-facing (Release Notes, Migration, Common Tasks), one PXE deep-dive, one comms templates page, plus four stretch goals.

### Final test-machine alignment

Deployed pending bits to `dvgs-testmachine`:

- `xfce4-appfinder.xml` (system-wide /etc/xdg) ✓
- `lightdm-gtk-greeter.css` ✓
- Plank dockitems in `/etc/skel/.config/plank/dock1/launchers/` (10 files) — needed ad-hoc copy with absolute `src` path; the playbook's `copy: src=config/etc-skel/ dest=/etc/skel/` task didn't propagate the new deeply-nested dotfile subtree

### Repo change: import_tasks consistency

Applied the same `include_tasks` → `import_tasks` fix to `roles/sudhanix-core/tasks/main.yml` as was done in `roles/common/tasks/main.yml` earlier. Tags inside `setup/default.yml` now visible at `--list-tasks` time. Nested includes inside `setup/default.yml` (lubuntu, lookandfeel, sudhanix-ux, sound, wallpaper) still use `include_tasks` per their existing pattern; tag filtering through them works at the include-line tag level (e.g. `--tags lookandfeel`, `--tags sudhanix-ux`).

### Investigate later

- The `copy:` module not propagating deeply-nested new dotfile subtrees in a playbook run when the destination parent doesn't exist. Affected: `/etc/skel/.config/plank/dock1/launchers/`. Workaround: ad-hoc copy with absolute src path. Probably needs a stat-then-create-directory chain, or split the copy into multiple steps with explicit directory creation.

---

## 2026-05-05 — LDAP Auth Fix: Decision

### Problem (recap from 2026-05-04 diagnosis)

`dvgs-testmachine` (Ubuntu 24.04 / Sudhanix 26): `do_start_tls failed` in nscd; 0/439 LDAP users resolving. LDAP server `ldap-srv.cttb` (10.11.1.25, 16.04 OpenLDAP) reachable on 389; 636 refused. PAM/NSS config syntactically correct.

### Root cause (localized)

The CTTB private CA (`roles/ldap-client/files/cttb-cacert.pem`, issued 2016‑08‑16, expired 2017‑08‑17) was never deployed into `/etc/ssl/certs/ca-certificates.crt` on clients — `roles/ldap-client/tasks/main.yml` points `tls_cacertfile` and `TLS_CACERT` at the system bundle but contains no `update-ca-certificates` task. STARTTLS therefore can't validate the server cert. Compounded on 24.04 by OpenSSL 3 rejecting SHA1 sigs, RSA <2048, and expired CAs by default — the 2016 cert is unlikely to satisfy any of these even if shipped.

### Decision: **Path C — re-issue server cert with modern CA, ship to clients**

Considered:

| Path | Why not |
|---|---|
| A. Disable TLS (`ssl off`) | Cleartext bind passwords on LAN — quick, but leaves the next admin to find it the hard way |
| B. `tls_reqcert never` + ship CTTB CA | Encryption without identity check — half-measure, still fails on a SHA1/expired chain under OpenSSL 3 |
| **C. Re-issue with modern CA, ship CA via `update-ca-certificates`** | **Chosen.** Proper fix; aligns with leaving 16.04 anyway |
| D. Migrate ldap-srv to 24.04 first | Out of scope this session; tracked separately |

### Original Path C plan ABANDONED — see live diagnosis below

The original plan (re-issue server cert with new CA, ship via `update-ca-certificates`) was based on the 2026-05-04 ad-hoc diagnosis. Live verification on 2026-05-05 invalidated nearly every premise. Nothing on lxc-ldap was modified.

### Live diagnosis on 2026-05-05 (what's actually true)

Reached lxc-ldap via: ssh `kit.chong@rui-desktop2.cttb -i ~/.ssh/id_ed25519`, `source ~/tt` (live agent has `cttb-os` RSA key loaded), then `ssh ldap` lands as `administrator@ldap-srv`. Sudo password = ansible vault password `4m1t0f0`.

| Earlier assumption | Live reality |
|---|---|
| CA private key on lxc-ldap | **Not present** at `/etc/ssl/private/cakey.pem`. Offline CA. Self-issued cert rotation impossible from this host. |
| 2016 CA cert in `roles/ldap-client/files/cttb-cacert.pem` reflects production | **Stale.** Production CA = `CTTB Root CA` (CN=`CTTB Root CA`, RSA-4096, SHA256, valid Jun 21 2017 → **Jun 21 2047**), 7347 bytes. Already in repo at `roles/cttb-ca-client/files/CTTB-Root-CA.crt` (identical SHA1 fingerprint `BE:68:55:C5:E0:0C:0E:1E:9C:43:1E:C1:3E:FB:BF:85:7D:03:88:0D`). |
| Server cert weak (RSA-1024 / SHA1) | **False.** Server cert = RSA-2048, SHA256, valid Jun 24 2019 → **Dec 31 9999**. Subject `CN=ldap-srv.cttb,OU=IT,O=City of Ten Thousand Buddhas,L=Ukiah,ST=CA,C=US`. Signed by CTTB Root CA. |
| SAN missing dNSName breaks OpenSSL 3 hostname check | **Mostly false.** Server cert SAN contains only `email:cttb-it@drba.org`. Per RFC 2818/6125, if SAN has zero `dNSName` entries, CN-fallback applies. OpenSSL 3 `s_client -starttls ldap -connect 10.11.1.25:389 -CAfile <CA> -verify_hostname ldap-srv.cttb -verify_return_error </dev/null` returns **`Verification: OK`** and **`Verify return code: 0 (ok)`**. |
| CA-trust gap on clients (root cause per 2026-05-04) | **False.** `cttb-ca-client` role exists in `plays/install-sudhanix-cslabs.yml` (after `ldap-client`). On dvgs-testmachine: `/usr/local/share/ca-certificates/CTTB-Root-CA.crt` is present, `grep -c "City of Ten Thousand Buddhas" /etc/ssl/certs/ca-certificates.crt` = 2 (CA in trust bundle). |
| STARTTLS handshake failing (`do_start_tls failed`) | **NOT FAILING right now.** From dvgs-testmachine: `ldapsearch -x -ZZ -H ldap://ldap-srv.cttb -b dc=cttb -s base` returns rc 0 with valid LDIF. `openssl s_client -starttls ldap -connect 10.11.1.25:389 -verify_return_error -verify_hostname ldap-srv.cttb </dev/null` returns OK. The 2026-05-04 `do_start_tls failed` from nscd may have been before `cttb-ca-client` ran on this host, or from a different code path — `journalctl -u nscd --since "1 hour ago"` shows **no recent entries**. |

### Real problem (working theory, not yet pinned)

`getent passwd | wc -l` on dvgs-testmachine = **439** (still local only). `getent passwd | awk -F: '$3 >= 10000'` = **1 entry** (likely `nobody`/65534, not LDAP). NSS is **not pulling from LDAP**, but **not because of TLS**. STARTTLS works.

Likely culprits, in order:
1. **`/etc/nsswitch.conf` not actually configured for LDAP** on this host (the `lineinfile` task in `roles/ldap-client/tasks/main.yml` may not have matched the default Ubuntu 24.04 nsswitch lines).
2. **libnss-ldap (legacy PADL, 2009-vintage) deprecated/broken on 24.04.** Package `libnss-ldap 265-5ubuntu3` is installed but is in-process and may not work with current glibc/NSS. Maintained replacement: `libnss-ldapd` + `nslcd`.
3. **`/etc/ldap.conf` (or `/etc/libnss-ldap.conf`) missing `base`, `uri`, or bind config.**
4. **nscd not invalidating its empty cache** for `passwd` after install (`nscd -i passwd` clears).

### Repo changes this session (kept; consistent with reality)

- `roles/ldap-client/files/cttb-cacert.crt` — pulled `CTTB Root CA` cert from server. Identical to `roles/cttb-ca-client/files/CTTB-Root-CA.crt` (verified by SHA1 fp). Redundant but harmless.
- `roles/ldap-client/tasks/main.yml` — added `install CTTB private CA into local trust source` task (copy + `update ca certificates` handler). **Redundant** with `cttb-ca-client` role; safe to revert in cleanup.
- `roles/ldap-client/handlers/main.yml` — created with `update ca certificates` handler.
- Deleted `roles/ldap-client/files/cttb-cacert.pem` (1480 bytes, expired 2017, never deployed).

### Capability acquired this session (use next session)

```bash
# Reach lxc-ldap as root:
ssh -i ~/.ssh/id_ed25519 kit.chong@rui-desktop2.cttb
source ~/tt              # attaches to live agent (PID 110862, socket /tmp/ssh-U7NQ8zGQ2Mfb/agent.110861)
ssh ldap                 # lands as administrator@ldap-srv
echo 4m1t0f0 | sudo -S -p '' <command>   # sudo password
```

The cttb-os key passphrase remains unknown; don't need it because kit.chong's running ssh-agent on rui-desktop2 has the key loaded.

### Resume next session — concrete next steps

Goal recap: make `getent passwd | wc -l` on dvgs-testmachine ≫ 439 (LDAP users resolving via NSS).

```bash
# from /Users/jc/Garden/external/cttb-ansible:
ANSIBLE_VAULT_PASSWORD_FILE=<(security find-generic-password -s CTTB_VAULT_PASS -w) \
    ansible -i inventory/hosts_os_upgrade.ini dvgs-testmachine.cttb -b -m shell -a '
echo "--- nsswitch ---";  cat /etc/nsswitch.conf | grep -E "^passwd|^group|^shadow"
echo "--- ldap.conf ---"; cat /etc/ldap.conf 2>/dev/null | grep -vE "^#|^$"
echo "--- libnss-ldap.conf ---"; ls -la /etc/libnss-ldap.conf 2>&1; cat /etc/libnss-ldap.conf 2>/dev/null | grep -vE "^#|^$"
echo "--- direct uid lookup test ---"; getent -s ldap passwd | wc -l
echo "--- nscd flush + retry ---"; nscd -i passwd 2>&1; sleep 1; getent passwd | wc -l
'
```

Decision tree based on output:
- `nsswitch.conf` lacks `ldap` on passwd/group/shadow → fix the `lineinfile` regexes in `roles/ldap-client/tasks/main.yml` to match 24.04's defaults.
- `ldap.conf` missing `base`/`uri` → debconf-driven write didn't take; fix the `debconf` tasks or template the file directly.
- `libnss-ldap` is the structural problem on 24.04 → migrate to `libnss-ldapd` + `nslcd` (separate daemon, modern, supported). Add new tasks to `roles/ldap-client/`, gate by Ubuntu version.

Validators (no specific user needed):
- V1: `getent passwd | awk -F: '$3 >= 10000' | wc -l` ≥ 1 (real one; today returns 1 for `nobody` only).
- V2: `getent -s ldap passwd | head -1` returns a non-empty entry (specifically queries the LDAP NSS source).
- V3: `ldapsearch -x -ZZ -H ldap://ldap-srv.cttb -b dc=cttb -s base` returns rc 0 (already passing today).

---

## 2026-05-05 — GRUB Menu + Plymouth Splash Visibility Fix

### Issue

After reboot of `dvgs-testmachine`, neither the GRUB menu nor the Plymouth splash were visible. Diagnosed via `/etc/default/grub`:

| Setting | Default (Ubuntu install) | Effect |
|---------|--------------------------|--------|
| `GRUB_TIMEOUT_STYLE=hidden` | menu hidden | Have to hold Shift/Esc at boot to see GRUB |
| `GRUB_TIMEOUT=0` | no countdown | GRUB jumps straight to default entry |
| `GRUB_CMDLINE_LINUX_DEFAULT=""` | no `splash` flag | Plymouth runs in text mode, no graphical splash |

### Fix

Added 3 `lineinfile` tasks to `roles/sudhanix-core/tasks/sudhanix-ux.yml`:

- `GRUB_TIMEOUT_STYLE=menu`
- `GRUB_TIMEOUT=3`
- `GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"`

Each notifies the `update grub` handler. Gated by `ansible_virtualization_type != "lxc"`. Deployed via `--tags sudhanix-ux`.

### Verified on dvgs-testmachine (post-deploy, pre-reboot)

- `/etc/default/grub` shows the new values
- `/boot/grub/grub.cfg` contains `linux ... ro quiet splash $vt_handoff` — splash flag baked into kernel cmdline

### Why the server role isn't affected

`roles/server/tasks/main.yml` deploys its own `default-grub` (with `nosplash debug`) for headless hosts. Servers don't use the `sudhanix-core` role, so the new `lineinfile` tasks don't run on them. Defaults remain headless-friendly.

### Tag dispatch reminder

`--tags grub` alone matches no tasks (because `setup/default.yml` includes `sudhanix-ux.yml` via `include_tasks`, which only exposes the `sudhanix-ux` tag at filter time). Use `--tags sudhanix-ux` to reach the GRUB tasks via the include.

---

## 2026-05-05 — Plymouth: macOS forks + missing source

### Issue 1: Source files never landed in repo

`roles/sudhanix-core/files/plymouth/sudhanix/` was supposed to contain the theme source committed in `76f1ec05`. It wasn't there. The `mkdir -p` + `cp` from `/tmp/sudhanix-plymouth-build/` may have hit a cwd issue. Now actually committed: 5 files (lotus.png, progress-bg.png, progress-fill.png, sudhanix.plymouth, sudhanix.script).

### Issue 2: macOS AppleDouble forks in initrd

`lsinitramfs` on dvgs-testmachine showed `._lotus.png`, `._progress-bg.png`, etc. alongside the real files. The original tarball was built on macOS with plain `tar czf`, which writes `._*` AppleDouble sidecars. Plymouth ignores them but they bloat the initrd.

### Fix

1. Repacked tarball with `tar --no-xattrs --exclude='._*' --exclude='.DS_Store'`. Uploaded clean version to storehouse.
2. Added defensive cleanup task in `roles/common/tasks/setup/default.yml`: `find /usr/share/plymouth/themes/sudhanix -name '._*' -delete`, notifies `update initramfs`.
3. Cleaned the host, re-ran `--tags plymouth`, handler fired.

### Verified post-fix

`lsinitramfs /boot/initrd.img-$(uname -r) | grep sudhanix` shows only the 5 real files.

### Note on `plymouth-set-default-theme`

Doesn't exist on Ubuntu 24.04 — the `plymouth` package ships only `plymouth` (client) and `plymouthd` (daemon). Equivalent operations are already done by the role: `update-alternatives --install` + `--set` + `update-initramfs -u`.

### CONFIRMED LIVE (post-reboot, 2026-05-05)

User rebooted dvgs-testmachine after the GRUB visibility fix and clean Plymouth tarball deploy:

- **GRUB menu** displays for 3 seconds with "Sudhanix GNU/Linux" entries ✓
- **Plymouth splash** shows the lotus + progress bar between GRUB and login ✓
- **lsb_release -a** post-login reports `Sudhanix 26 / storehouse / 26` ✓

End-to-end branding chain verified: PXE → autoinstall → GRUB ('Sudhanix') → Plymouth (lotus) → login banner ('Sudhanix 26') → MOTD (wiki.cttb primary) → desktop session. Ready for mass rollout from a branding standpoint.

### Side fix while at it: `/etc/resolver/cttb` on the Mac

Stale macOS resolver was pointing at `10.11.1.5` (unreachable). Updated to `10.11.1.19` (dnsmasq.cttb). Now `dvgs-testmachine.cttb` and other `.cttb` names resolve from the Mac without needing IP overrides. The redundant `ansible_host=10.11.30.60` added earlier in the upgrade inventory could be reverted but is being kept as belt-and-suspenders.

---

## 2026-05-05 (continued) — LDAP Auth: Already Working, Reframe + Cleanup

### Outcome

**Nothing was broken.** NSS+LDAP auth on `dvgs-testmachine` is functioning end-to-end. Prior session's "0/439 LDAP users resolving" finding was an artefact of a wrong validator threshold (`uid >= 10000`). Real LDAP `uidNumber`s are 2001–9999, all of them already populated through `getent`.

### Live evidence

- `getent passwd | wc -l` = 439 = **40 local + 399 LDAP**. The 399 figure is an exact match against `ldapsearch -x -ZZ -b dc=cttb '(objectClass=posixAccount)' dn | grep -c '^dn:'` on `ldap-srv.cttb` → 399.
- 399 entries have `/nfs/home/<name>` paths (LDAP-sourced telltale).
- `getent passwd frank.liu` → `frank.liu:*:2001:2001:Frank Liu:/nfs/home/frank.liu:/bin/bash` ✓
- `getent passwd 2001` → same record (lookup by uidNumber works).
- `su -c id frank.liu` → `uid=2001(frank.liu) gid=2001(it) groups=2001(it)` (NSS resolves primary group "it" from LDAP).
- `ldapsearch -x -ZZ -H ldap://ldap-srv.cttb` → rc 0 (STARTTLS clean).
- Real SSH attempt as `john.chandara` from `cosmicbook` (10.11.24.24) — wrong password, but auth.log shows full LDAP bind round-trip:

  ```
  sshd[11085]: pam_unix(sshd:auth): authentication failure ... user=john.chandara
  sshd[11085]: pam_ldap: error trying to bind as user "uid=john.chandara,ou=People,dc=cttb" (Invalid credentials)
  sshd[11085]: Failed password for john.chandara from 10.11.24.24 port 56167 ssh2
  ```

  LDAP error 49 ("Invalid credentials") is the **server** rejecting the password — meaning pam_ldap loaded, resolved DN, opened connection, completed STARTTLS, sent bind, and got a clean wrong-password rejection. Auth path is green.

### Validators (revised — V1 from prior session was wrong threshold)

| ID | Check | Result |
|----|-------|--------|
| VR1 | `getent passwd \| grep -c "/nfs/home/"` ≥ 50 | **399** ✓ |
| VR2 | `getent passwd frank.liu` non-empty with uid 2001 | ✓ |
| VR3 | `id frank.liu` returns LDAP `it` group | ✓ |
| VR4 | `ldapsearch -x -ZZ -H ldap://ldap-srv.cttb -b dc=cttb -s base` rc 0 | ✓ |
| VR5 | sshd journal logs `pam_ldap: ... bind ... Invalid credentials` for failed login (proves bind round-trip) | ✓ |

### Repo cleanup landed this session

The 2026-05-05 (earlier) ad-hoc patch to `roles/ldap-client` was based on the wrong premise. Reverted:

- `plays/install-sudhanix-cslabs.yml` — swapped `cttb-ca-client` to run **before** `ldap-client`. This makes the trust anchor present at the moment ldap-client configures `tls_cacertfile`, removing the need for ldap-client to ship its own copy of the CA. Order is now: `sudhanix-core, time-server, cups-client, cttb-ca-client, ldap-client, nfs-home`.
- `roles/ldap-client/tasks/main.yml` — dropped the `install CTTB private CA into local trust source` task (and its `ldap_c_tls`/`cttb_ca` tags).
- `roles/ldap-client/handlers/main.yml` — deleted (the `update ca certificates` handler lived only to support the dropped task; cttb-ca-client owns CA install + refresh).
- `roles/ldap-client/files/cttb-cacert.crt` — deleted (was identical SHA1 to `roles/cttb-ca-client/files/CTTB-Root-CA.crt`).
- `roles/ldap-client/files/cttb-cacert.pem` — deleted (was the **2016 expired** stub from the original repo state, never deployed; no longer reachable from any task).

`roles/ldap-client/` is now back to the role responsibility it advertises: configure libnss-ldap/pam_ldap, write `/etc/ldap.conf`, point `tls_cacertfile` at the system bundle. Trust anchor is `cttb-ca-client`'s job.

### Open follow-ups (resolved later same session)

- ~~**NFS export ACL gap**~~ — **Resolved.** Added `10.11.30.0/24` to `/etc/exports` on `fileserver` (the LXD container `fs` on `srv-nas`, Ubuntu 16.04, reached via `kit.chong@rui-desktop2 → administrator@fileserver` with the `tt` agent loaded). Backup at `/etc/exports.bak.20260505_180731`. `exportfs -ra` reloaded; `showmount -e fileserver` now lists `10.11.30.0/24,10.11.16.0/24,10.11.10.0/24,10.11.9.0/24`. Autofs on `dvgs-testmachine` immediately mounts `/nfs/home/<user>` on access (verified via `findmnt`). Existing comment in `/etc/exports` already hinted the intent ("10.11.30.97: rui-desktop for testing") but the export line itself was never updated; this catches up to that.
- ~~**common role include bug**~~ — **Resolved.** Root cause: ansible reports `distribution=Sudhanix, major=26` on Sudhanix-branded hosts (because the role overrides `/etc/os-release` early), so `lookup('first_found')` searched for `Sudhanix_26.yml` which didn't exist; `skip:true` returned an empty string; `include_tasks: ""` died with "No include file was specified to the include". Fix in commit `f3e6e02d`: (a) `roles/common/tasks/main.yml` now uses `loop: "{{ q('ansible.builtin.first_found', params, errors='ignore') }}"` so a no-match cleanly skips the task, and (b) added `roles/common/tasks/setup/Sudhanix_26.yml` that `import_tasks: Ubuntu_24.yml`, so any future Ubuntu-24-specific work auto-applies on Sudhanix without a second edit. `--check` against dvgs-testmachine now passes 134 tasks (was 43 before).
- ~~**john.chandara forgot LDAP password**~~ — **Resolved.** Reset via the *temporary olcRootPW* technique on `ldap-srv`: by default no `olcRootPW` is set on `olcDatabase={1}mdb,cn=config`, so the rootDN `cn=admin,dc=cttb` has no usable bind credential. Procedure (executed via SASL EXTERNAL over `ldapi:///`): hash an ephemeral secret with `slappasswd`, add it temporarily as `olcRootPW` on the data db via `ldapmodify`, perform the standard ldappasswd extop against the user DN to install the new value, then delete `olcRootPW` to restore the prior config. Bash `trap cleanup EXIT` ensured the temporary admin entry is removed even on error. Stored hash format flips from `{crypt}$1$...` (MD5) to `{SSHA}` (slapd's default for ldappasswd extop) — both verify fine on bind; no client config change required.
- ~~**sudhanix-core Zoom client install**~~ — **Resolved.** Root cause: `http://storehouse.cttb/ansible/zoom_amd64.deb` returns the storehouse h5ai index page (HTTP 200, `text/html`) instead of the .deb. The asset is missing on the server; apt downloads HTML, `ar` can't parse it → "E:Invalid archive signature". Fix in `roles/sudhanix-core/tasks/sw.yml`: switch the Zoom URL to upstream (`https://zoom.us/client/latest/zoom_amd64.deb`) gated by an overridable `zoom_deb_url` var. Zoom releases monthly so caching on storehouse turns into a recurring chore; pulling from upstream keeps the lab current with no maintenance. Lab proxy (e2guardian → squid on srv-gw, picked up via `global_proxy`) carries the request fine. Verified install via ansible apt module on dvgs-testmachine — no signature error, `changed=false` (Zoom already at upstream version).

### sudoers for LDAP `it` group

Added `roles/ldap-client/tasks/main.yml` task: deploy `/etc/sudoers.d/it-group` with `%it ALL=(ALL:ALL) ALL` (password required, matches default `%sudo` policy), validated via `visudo -cf %s`. Tagged `sudoers, acl`. Verified on dvgs-testmachine: `visudo -c` parses cleanly, sudoers drop-in is in effect for any user whose primary or supplementary group is `cn=it` (gidNumber 2001).

### Existing IT shared accounts (informational)

While probing identity options, found `it.dvgs` (uid=6194, gid=2006/dvgs-students) and `it.dvbs` (uid=5179, gid=2005/dvbs-students) created 2025-12-10. Both have userPasswords set ({crypt}$6$ = SHA-512). Useful as shared role accounts where audit traceability isn't required. Not modified this session.

### Sudhanix welcome window with LDAP-persisted dismissal

End-to-end first-login welcome flow. The app shows once per user (across every CTTB lab machine) until the user ticks "Don't show this again", which writes a flag into LDAP that all hosts read on subsequent logins.

**Server side (live + captured in `roles/ldap-schema-sudhanix`):** new schema entry under `cn=sudhanix,cn=schema,cn=config` defines `sudhanixWelcomeDismissed` (BOOLEAN, single-valued, OID `1.3.6.1.4.1.99999.1.1.1`) and the auxiliary objectClass `sudhanixUser` (OID `1.3.6.1.4.1.99999.1.2.1`) which MAY hold it. New ACL `{0}to attrs=sudhanixWelcomeDismissed by self write by * read` on `olcDatabase={1}mdb,cn=config` lets each user toggle their own flag and nobody else's. Both LDIFs are idempotent; the ansible role probes for presence before applying.

**Client side (`roles/sudhanix-core/files/welcome/` + `tasks/sudhanix-welcome.yml`):**
- `sudhanix-welcome` — Python+GTK3. Reads the user's cleartext password from a per-uid token file in `/run/sudhanix-tokens/`, calls `ldapsearch -y <token>` to read the flag (the password never lands on argv), and on dismissal calls `ldapmodify` to add `objectClass: sudhanixUser` if missing and set `sudhanixWelcomeDismissed: TRUE`. Fail-soft on every error path (logs to stderr, exits 0) so the welcome UX can never block a login.
- `sudhanix-cache-token` — pam_exec hook with `expose_authtok=1`, writes the password into `/run/sudhanix-tokens/<uid>.tok` mode 0600 owned by the user.
- `sudhanix-shred-token` — pam_exec session-close hook that `shred -uz` removes the file.
- `/etc/tmpfiles.d/sudhanix-tokens.conf` — declares `/run/sudhanix-tokens` as `1733 root:root` so the dir exists at boot and only owners can read their own files.
- `/etc/xdg/autostart/sudhanix-welcome.desktop` — XDG autostart for XFCE/LXQt/LXDE.
- PAM hooks added directly to `/etc/pam.d/lightdm` (and `sddm`/`gdm-password` if those files exist on a host) AFTER `@include common-auth`, so SSH and sudo do not cache passwords. Hooks via `lineinfile`, idempotent.
- Switched away from python3-ldap apt dep — apt.cttb's mirror does not carry the package, AND the deb822 sources file was broken anyway after Sudhanix branding (see next section). Subprocess + ldap-utils CLI is the right call here regardless.

**Apt codename fix.** Sudhanix branding rewrites `/etc/os-release` with `VERSION_CODENAME=storehouse`. On every subsequent ansible run, fact-gathering reports `ansible_distribution_release=storehouse`, and `roles/common/templates/ubuntu.sources.j2` rendered a deb822 file pointing at `apt.cttb/mirrors/ubuntu storehouse,storehouse-updates,...` — none of which the mirror carries. `apt update` then 404'd on every suite. Fix: introduced an `apt_codename` variable in both `roles/common/vars/Ubuntu_24.yml` and `roles/common/vars/Sudhanix_26.yml`, both pinning to `noble`; the template now substitutes it instead of the rebrand-affected fact. Vanilla Ubuntu 24 hosts get `noble` from `Ubuntu_24.yml`, Sudhanix-branded hosts get `noble` from `Sudhanix_26.yml` (auto-loaded via the role's `include_vars` loop).

**Verified on dvgs-testmachine:** files deployed at expected paths (`/usr/local/bin/sudhanix-welcome`, `/usr/local/sbin/sudhanix-{cache,shred}-token`); PAM hooks present in `/etc/pam.d/lightdm`; `/run/sudhanix-tokens` exists with mode 1733; `python3 -m py_compile` clean on the welcome app; `ldapsearch -y <token-file>` smoke test as john.chandara reading `sudhanixWelcomeDismissed` returns rc 0. The full GUI flow (window pops → checkbox → write back → second login is silent) needs a real graphical login to exercise; the plumbing is all in place.


## 2026-05-06 — LDAP login: Sudhanix overrides not applied + first-login bootstrap

**Symptom (reported by JC after first LDAP login as `john.chandara` on dvgs-testmachine):** desktop comes up vanilla XFCE — no top panel customization, no Plank dock, theme not WhiteSur-Dark, wallpaper points at `/usr/share/wallpaper` with no rotation. NFS home export works (re-login on the same machine returns the same `$HOME`). First login showed a black screen briefly (lightdm died and respawned); second login painted normally.

### Side observations from the same login attempt

1. **lightdm-gtk-greeter segfault in `libcairo.so.2.11800.0`** — `kernel: lightdm-gtk-gre[10669]: segfault at 10 ip 00007bcc8323eb14 sp 00007ffcea7cf8a8 error 4 in libcairo.so.2.11800.0[7bcc831d5000+f1000]`. PAM session for `lightdm` is then closed, `session-c3.scope` deactivated. Not blocking — lightdm respawns.
2. **PAM noise** that's normal-but-loud:
   - `pam_succeed_if(lightdm:auth): requirement "user ingroup nopasswdlogin" not met by user "john.chandara"` — expected; only the `nopasswdlogin` group bypasses prompts.
   - `pam_unix(lightdm:auth): authentication failure ... user=john.chandara` — expected; LDAP user not in `/etc/passwd`, falls through to `pam_ldap`.
   - `pam_ldap: error trying to bind as user "uid=john.chandara,ou=People,dc=cttb" (Invalid credentials)` — typo on first attempt (or `Caps Lock` from the Logitech Mac-layout keyboard from the 04-16 session).
   - `Error getting user list from org.freedesktop.Accounts: GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown: The name org.freedesktop.Accounts was not provided by any .service` — `accountsservice` not installed (or masked) on Sudhanix-26 lab images. Means LightDM has no per-user session memory; the system-wide `user-session=xfce` in `lightdm.conf` is what's binding the session.
3. **`nfs4: Deprecated parameter 'intr'`** spammed in dmesg — Ubuntu 24.04 kernel dropped `intr`; auto.master / auto.nfs.j2 still pass it.
4. **Zen Browser → desktop drag-and-drop fails** with "The specified location is not supported" (screenshot 5). Zen is a Flatpak (`io.github.zen_browser.zen`); its sandbox has no write access to `xdg-desktop`, so xfdesktop's drop target rejects the operation.

### Root-cause analysis of the missing Sudhanix overrides

System defaults are deployed correctly by `roles/sudhanix-core/tasks/lookandfeel.yml` + `sudhanix-ux.yml` + `wallpaper.yml`:
- `/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/{xsettings,xfwm4,xfce4-panel,xfce4-desktop,xfce4-keyboard-shortcuts,thunar,xfce4-appfinder}.xml`
- `/etc/skel/.config/{plank/dock1/launchers/*.dockitem, lxqt/globalkeyshortcuts.conf, autostart/LXTerminal.desktop, fcitx/*, Kingsoft/Office.conf}`
- `/etc/xdg/autostart/{devilspie2,clean-chrome-locks,sudhanix-welcome}.desktop`
- LightDM seat config forces `user-session=xfce` so `~/.dmrc` absence doesn't matter.

Two failures combine to break the first-login experience for LDAP users:

1. **`pam_mkhomedir` is not enabled** on lab machines. `roles/ldap-client/tasks/main.yml` sets `libpam-runtime/profiles = "unix, ldap, systemd"` and runs `pam-auth-update`, but `mkhomedir` is **not in the multiselect**, so `/etc/pam.d/common-session` does not include `pam_mkhomedir.so`. Result: `/etc/skel` is **never** copied into LDAP user homes. Plank launchers, fcitx config, autostart `LXTerminal.desktop`, etc. simply do not exist in `~/.config/`.
2. **Stale 20.04 LXQt configs persist on the NFS home.** john.chandara's home was created on the NFS server during a previous Ubuntu 20.04 / Lubuntu (LXQt) deployment. That home contains `~/.config/xfce4/xfconf/xfce-perchannel-xml/*.xml` (and possibly `~/.config/lxqt/`, `~/.config/openbox/`, `~/.gtkrc-2.0`, `~/.dmrc`) from the legacy session. XFCE 4.18 reads user-level perchannel-xml *in preference to* `/etc/xdg`, so our system defaults are silently shadowed.

This explains every concrete symptom: no Plank dock (no skel-copied launchers + no system dconf for the launcher order), wrong theme (stale `~/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml` overrides `WhiteSur` / `WhiteSur-dark`), wrong wallpaper (stale user-level `xfce4-desktop.xml` points at `/usr/share/wallpaper` from the old install), no rotation (no `backdrop-cycle-enable=true` in the user override).

### Fix design — three parts

**A. Enable `pam_mkhomedir`** in `roles/ldap-client/tasks/main.yml`: change the `libpam-runtime/profiles` debconf value from `unix, ldap, systemd` to `unix, ldap, systemd, mkhomedir`, then re-run `pam-auth-update` non-interactively. After this, every fresh LDAP user gets `/etc/skel` copied into `$HOME` on first login. (Existing users with pre-populated NFS homes still need part B — mkhomedir does nothing if the home dir exists.)

**B. First-login bootstrap script (`/usr/local/sbin/sudhanix-firstlogin`)** wired in via a new role file `roles/sudhanix-core/tasks/sudhanix-firstlogin.yml` and an XDG autostart entry. The script:
   - Checks marker `~/.config/sudhanix/v26-bootstrapped`. If present → exit 0 silently.
   - Quarantines pre-Sudhanix-26 user configs by moving any existing `~/.config/xfce4`, `~/.config/lxqt`, `~/.config/openbox`, `~/.gtkrc-2.0` aside to `~/.config/.pre-sudhanix-26.<timestamp>/`. Preserves user data (Documents, Desktop, Downloads, browser profiles) untouched.
   - Copies plank launchers from `/etc/skel/.config/plank/` if absent in the user home.
   - Sets `~/.dmrc` to `[Desktop]\nSession=xfce` so even if a host re-introduces accountsservice the session preference is correct.
   - Writes the marker (`<version>\n<timestamp>\n<hostname>\n`) and exits 0.
   - Fail-soft: every step wrapped, failures logged to `~/.cache/sudhanix-firstlogin.log`, exit 0 always so a buggy bootstrap can never block login.

   The autostart entry (`/etc/xdg/autostart/sudhanix-firstlogin.desktop`) runs *before* `sudhanix-welcome.desktop` (lower-cased name sorts first; explicit `X-GNOME-Autostart-Phase=Initialization` for systems that honor it). After it runs once, xfsettingsd picks up the now-cleared user dotfiles + system defaults from `/etc/xdg`.

**C. System dconf for Plank** at `/etc/dconf/db/site.d/00-plank-dock1` declaring the canonical launcher list, plus `/etc/dconf/profile/user` with `user-db:user / system-db:site`, then `dconf update`. Plank reads the launcher order from dconf, not from the `.dockitem` files alone — without this layer the launchers exist on disk but the dock comes up empty.

### Side fixes bundled into this entry

- **NFS `intr` deprecation:** drop `intr` from `roles/nfs-home/files/auto.master` and `templates/auto.nfs.j2`. The kernel ignores it on 24.04 and the deprecation warning floods dmesg / makes real NFS errors hard to spot.
- **Zen Browser drag-to-desktop:** add `flatpak override --system --filesystem=xdg-desktop --filesystem=xdg-download io.github.zen_browser.zen` task in `roles/sudhanix-core/tasks/sw-browser.yml` after the `flatpak install` step. `xdg-download` included so users can drag-save into `~/Downloads` too.
- **Greeter cairo segfault:** captured for follow-up. Hypothesis is that `lightdm-gtk-greeter.css`'s `box-shadow: inset 0 1px alpha(white, 0.08)` + alpha-blended backgrounds trip a known cairo 1.18 regression on cold-cache greeter start. Mitigation deferred until reproduced under `coredumpctl` — workaround in the meantime is "log in twice", which is what JC already observed. Not in critical path; not blocking rollout because the greeter recovers.

### Validators

| Fix | Check |
|-----|-------|
| pam_mkhomedir | `grep -q pam_mkhomedir /etc/pam.d/common-session` returns 0 after deploy. Fresh `useradd --skel /etc/skel testldapnew` then login → `~/.config/plank/dock1/launchers/com.google.Chrome.dockitem` exists. |
| First-login bootstrap | Login as `john.chandara` post-deploy → `[ -f ~/.config/sudhanix/v26-bootstrapped ]`. Pre-existing `~/.config/xfce4` quarantined under `~/.config/.pre-sudhanix-26.*/`. Top panel + WhiteSur-Dark + rotating wallpaper all visible after re-login. |
| Plank dconf | As fresh user: `dconf read /net/launchpad/plank/docks/dock1/launchers` returns the canonical launcher list with no per-user write needed. |
| NFS intr | `dmesg | grep -i 'Deprecated parameter'` empty after re-mount of `/home/...`. |
| Zen drag-drop | `flatpak info --show-permissions io.github.zen_browser.zen | grep filesystems` includes `xdg-desktop;xdg-download`. Manual: drag image from Zen → desktop, file appears with no error dialog. |
| Greeter segfault | Cold boot 5×; `journalctl -u lightdm --since boot | grep -E 'segfault|cairo'` zero hits across all five. (Deferred; hypothesis only.) |

### Greeter cairo segfault — found in journal, narrowed, partial fix

`journalctl --no-pager | grep -iE 'lightdm-gtk-gre.*(segfault|cairo)'` confirms the crash:

```
May 04 15:23:28 dvgs-testmachine kernel: lightdm-gtk-gre[3594]:  segfault at 10 ip 000076d11863eb14 sp 00007ffd1cfdf328 error 4 in libcairo.so.2.11800.0[76d1185d5000+f1000]
May 06 08:47:56 dvgs-testmachine kernel: lightdm-gtk-gre[10669]: segfault at 10 ip 00007bcc8323eb14 sp 00007ffcea7cf8a8 error 4 in libcairo.so.2.11800.0[7bcc831d5000+f1000]
```

Both crashes hit the same offset within `libcairo.so.2.11800.0` (`ip - mapping_base = 0x69b14` in both cases) — deterministic, not a race. `error 4` = user-mode read fault; `at 10` = NULL+0x10 dereference, characteristic of a NULL struct/surface pointer being passed into a draw routine.

Same boot logs show GTK CSS parse errors immediately preceding each crash:

```
xfce4-notifyd[*]: Theme parsing error: lightdm-gtk-greeter.css:16:14: not a number
xfce4-notifyd[*]: Theme parsing error: lightdm-gtk-greeter.css:16:14: Expected a string.
xfce4-notifyd[*]: Theme parsing error: lightdm-gtk-greeter.css:71:14: not a number
xfce4-notifyd[*]: Theme parsing error: lightdm-gtk-greeter.css:71:14: Expected a string.
```

Lines 16 and 71 of `roles/sudhanix-core/files/config/lightdm-gtk-greeter.css` were both `font: bold;`. The GTK CSS `font` shorthand wants the full `<style> <variant> <weight> <size> <family>` form — a bare keyword is rejected. Fix: `font-weight: bold;` (replaced both occurrences).

**Honest scope of the fix.** The CSS parse errors are real bugs and worth fixing on their own merits. They are *not* proven to cause the libcairo crash — GTK's CSS parser doesn't call into libcairo, and the rules with the bad `font` shorthand may be silently dropped before they ever reach the renderer. The cairo crash sits in a different code path and matches the signature of known cairo 1.18 box-shadow + alpha-blend regressions — our greeter CSS uses `box-shadow: inset 0 1px alpha(white, 0.08)` and `box-shadow: inset 0 -1px alpha(black, 0.4)`, which are exactly the cases reported upstream. If first-login still segfaults after the parse-error fix, the next move is to strip the `box-shadow` rules. With `systemd-coredump` now installed + the `cttb-coredump-upload` pipeline (below), the next reproduction will land in `/public/coredumps/<host>/` automatically and we can analyze the actual frame instead of guessing.

### Coredump capture pipeline (storehouse + clients)

To stop guessing on next-time crashes:

**Server (`storehouse.cttb`)** — added `/public/coredumps/` as a WebDAV drop-zone. nginx `location /public/coredumps/` provides anonymous read (autoindex) + anonymous PUT/MKCOL with an 8 GB body cap and per-host `create_full_put_path`. WebDAV verbs limited to `GET HEAD PUT MKCOL` — no DELETE or MOVE, so cleanup is filesystem-side only. A `/etc/cron.daily/storehouse-coredumps-prune` script ages files out at 90 days. Switched from `nginx` to `nginx-extras` to pick up `dav-ext` (the basic `nginx-core` package on 22.04 has the dav module but the manti-X h5ai listing leans on the extras for nice rendering). Bumped `storehouse_subdirs` to include `public/coredumps`.

**Client (`common` role, every host)** — added `systemd-coredump` to `basic_software` so the kernel `core_pattern` re-points to the systemd handler. Verified on dvgs-testmachine: `core_pattern = |/usr/lib/systemd/systemd-coredump %P %u %g %s %t ...`. Added `/usr/local/sbin/cttb-coredump-upload` (POSIX sh, scans `/var/lib/systemd/coredump/core.*.{zst,xz,lz4}`, drops a `<core>.uploaded` sentinel after each successful PUT, exits 0 on any failure so transient network hiccups don't poison the timer's last-run state). Wrapped in `cttb-coredump-upload.{service,timer}` — `OnBootSec=5min OnUnitActiveSec=10min Persistent=true`. End-to-end PUT/GET round-trip verified from dvgs-testmachine: `mkcol HTTP=201 → put HTTP=201 → get returns content`. Timer is active, `summary: uploaded=0 failed=0 skipped=0` on first run (clean state, no dumps yet).

**Homepage** — added a "Coredumps" section to `roles/storehouse/files/index.html` with a one-paragraph description, the manual-upload `curl` recipe, and a browse link to `/public/coredumps/`. Cross-link to `IT:Storehouse` for the wiki write-up.

### Coredump pipeline — second pass: auth + magic-byte validation

The "wide open within .cttb" first cut had two real risks: (a) any device on the campus network could enumerate other hosts' dumps, and dumps capture raw process memory at the moment of crash; (b) anonymous PUT meant anyone could pollute the dropzone with arbitrary files. Both addressed in a follow-up:

**Read auth.** `nginx-extras` `location /public/coredumps/` now requires HTTP basic auth (`administrator` / campus admin password). The htpasswd is bcrypt-hashed via `community.general.htpasswd` (`python3-passlib` added as a dep on storehouse). Test passes: anon GET → 401, authed GET → 200, anon PUT → 201 (no auth), wrong-password GET → 401.

**Anonymous-write split.** PUT no longer goes to `/public/coredumps/`. Instead, `/public/coredumps-in/<host>/<file>` aliases to a staging directory (`/var/lib/nginx/coredumps-staging/`) that is NOT public-readable. A small POSIX script (`/usr/local/sbin/coredumps-validate-mover`) wrapped in a 30-second systemd timer reads the first 8 bytes of every staged file, matches against an allowlist of known coredump compression / format magics:

| Format | Magic | Source |
|---|---|---|
| zstd | `28 b5 2f fd` | systemd-coredump default on 24.04+ |
| xz   | `fd 37 7a 58 5a 00` | systemd-coredump default on older |
| lz4  | `04 22 4d 18` | rare |
| ELF  | `7f 45 4c 46` | `Compress=no` in coredump.conf |

Promoted files land at `/srv/storehouse/public/coredumps/<host>/<file>` with `www-data` ownership; rejected files move to `/srv/storehouse/private/coredumps-rejected/<host>/<ts>-<file>` and a `coredumps-validate` syslog tag captures the audit trail.

Anonymous write stays anonymous because gating it on credentials would mean shipping the credential to every lab host — credentials baked into a hundred student machines are effectively public. The magic-byte gate provides most of what auth would (rejecting garbage uploads) without that operational cost. The split is what makes it safe.

**Adversarial smoke-test from dvgs-testmachine.** Three PUTs (good zstd / HTML garbage / synthetic), wait 35s for the validator timer, authed GET of the host's dropzone. Result: only the legitimate zstd appeared in `/public/coredumps/dvgs-testmachine/`; HTML and synthetic-but-not-coredump went to quarantine; staging emptied. End-to-end with the actual `cttb-coredump-upload.service` and a synthesized dump in `/var/lib/systemd/coredump/` also worked: client uploads via `/public/coredumps-in/`, validator promotes within 30s, authed read shows the dump.

**Client URL switch.** `/usr/local/sbin/cttb-coredump-upload` now PUTs to `/public/coredumps-in/<host>/<basename>` instead of `/public/coredumps/<host>/<basename>`.

**Wiki.** `IT:Storehouse` updated with a full "Coredump drop-zone" section: motivating cairo segfault story, architecture (read/write URL split, why anonymous write is safe), the validator's accept-rule table, retention policy, and how to fetch + analyze a dump (including the `ddebs.ubuntu.com` `libcairo2-dbgsym` quirk). Published 2026-05-06 via `wikitools/wiki-edit.sh`.



### Wiki access control: AccessControl out, Lockdown in (with custom namespaces)

The wiki had `Extension:AccessControl` 6.0 plumbing (per-page `<accesscontrol>IT</accesscontrol>` tags + group pages in `MediaWiki:Group-IT`) but it was effectively dead on MW 1.43. AccessControl's primary hook is `ParserBeforeStrip`, which was retired from `HookRunner` in modern MediaWiki — only `ParserBeforeInternalParse` remains. The fallback path through `getUserPermissionsErrors → onUserCan → userVerify()` never sets `$result = false`; protection only "worked" as a side-effect of `doRedirect()` issuing `header(Location)` + `exit()`. Setting `$wgAccessControlRedirect = false` (to get an in-place deny instead of a URL change) therefore disabled protection entirely — anonymous users got the full page body. We confirmed this with a logging-injected `onParserBeforeStrip` that never fired on actual page views.

Switched to **Extension:Lockdown** (REL1_43, commit `120d6fd`). Lockdown restricts whole namespaces by MediaWiki user group, doesn't depend on dead hooks, and produces a clean "Login required" page (URL stays put, body is the standard MW login prompt). The model is coarser than per-page tags but a much better fit for how the IT pages were already organized — every page that needed protection already used an `IT:` title prefix that was being interpreted as a literal in NS_MAIN.

**Role changes** (`roles/mediawiki/`):
- `defaults/main.yml` got three new generic vars: `mediawiki_extra_namespaces`, `mediawiki_user_groups`, `mediawiki_lockdown` (rules dict shaped as `{ namespace_name: { action: [groups...] } }`).
- `templates/LocalSettings.php.j2` now generates the namespace defines, custom group permissions, and `$wgNamespacePermissionLockdown` rules from those vars. AccessControl-specific config (`$wgAccessControlRedirect`) and the AccessControl extension's source patches were dropped. A new `remove stale AccessControl extension` task deletes the on-disk extension folder.
- New play `plays/wiki-add-group-users.yml` promotes users into the custom groups via `createAndPromote.php --force --custom-groups`.

**Pre-emptive admin namespaces** (`host_vars/wiki-2404/main.yml`):

| ID   | Name      | Group  |
|------|-----------|--------|
| 3000 | IT        | it     |
| 3001 | IT_talk   | it     |
| 3010 | DRBU      | drbu   |
| 3011 | DRBU_talk | drbu   |
| 3020 | DVGS      | dvgs   |
| 3021 | DVGS_talk | dvgs   |
| 3030 | DVBS      | dvbs   |
| 3031 | DVBS_talk | dvbs   |
| 3040 | CTTB      | cttb   |
| 3041 | CTTB_talk | cttb   |

Each non-talk namespace gets `read/edit/create/move = [<group>]`; talk gets `read/edit = [<group>]`. The 9 IT users from the old `MediaWiki:Group-IT` page (Admin, Holysquirrel24, James Nguyen, Jay Tobias, Jchandara, Jerry.hsu, Kit Chong, Rui Liu, Spike Morelli) were promoted into `it` via the new playbook. DRBU/DVGS/DVBS/CTTB groups are empty until membership lists are filled in.

**Page migration.** 53 legacy `IT:`-prefixed pages were sitting in NS_MAIN with the colon as a literal title character. Once `NS_IT=3000` was registered, `/wiki/IT:Foo` resolved to NS_IT (empty + locked), orphaning the actual content. The MW move API (and `MovePage::moveIfAllowed`) no-op when the source's prefixed-text matches the target's, which they did here because legacy `NS_MAIN:"IT:Foo"` and new `NS_IT:"Foo"` both display as `"IT:Foo"`. Switched to a one-off `Maintenance` script (`/tmp/move_to_ns_it.php`) that does a direct `UPDATE page SET page_namespace=3000, page_title=ucfirst(rest)` — bypasses the same-prefix check, refreshLinks job-queue catches up the link tables. 53 canonical `IT:Foo` pages migrated, 37 `IT:_Foo` / `IT: Foo` underscore/space-variant duplicates left in NS_MAIN as orphans for separate cleanup.

**Verified.** Anonymous `GET /wiki/IT:Ansible` returns HTTP 200 with `<title>Login required - CTTB Wiki</title>`; `Special:AllPages?namespace=3000` shows "(IT namespace)" header. Database state: `SELECT COUNT(*) FROM page WHERE page_namespace=3000` → 54 (53 migrated + 1 seed `IT:Welcome`).

**Mbox infrastructure imported earlier in the session is unaffected** — Module:Message_box, the 9 meta-templates (Ambox/Cmbox/…/Dmbox), 24 supporting Lua modules, 6 TemplateStyles CSS pages, and 10 Commons SVG icons all still work; they just no longer have AccessControl's notice as a direct caller. `MediaWiki:Accesscontrol-info`, `CTTB Wiki:Deny user`, `CTTB Wiki:Deny anonymous`, `MediaWiki:Group-IT`, and `[[IT]]` (the legacy access-list page) are now orphaned artifacts and can be deleted in a follow-up cleanup.

### Wiki access control: deny-message migration + orphan cleanup

Follow-up to the AccessControl→Lockdown switch. With AccessControl gone, the friendly Mbox-styled deny notices (`MediaWiki:Accesscontrol-info`, `CTTB Wiki:Deny user`, `CTTB Wiki:Deny anonymous`) were dead weight — Lockdown bypasses them entirely and routes through MediaWiki's standard permission-error pipeline. Carried the same Audience-controlled-content notice into the three messages that pipeline actually renders:

| Message | Triggered by | What it shows |
|---|---|---|
| `MediaWiki:Loginreqpagetext` | Anonymous visitor — MW's `loginrequired` flow | Friendly Mbox: "Audience controlled content … log in with your campus account" |
| `MediaWiki:Badaccess-groups` | Logged-in user lacking the required group(s) — Lockdown returns this from `userCan` (Hooks.php:154) with `$1` = comma-listed allowed groups, `$2` = group count | Same Mbox + the explicit allowed-group list |
| `MediaWiki:Badaccess-group0` | Logged-in user, namespace explicitly locked to no groups (Hooks.php:135) | Same Mbox, "contact IT — likely misconfigured" wording |

All three use `{{Ambox|type=content|text=...}}` so they pick up the same border + warning-triangle icon used by the rest of the wiki's notice system. Verified end-to-end: anonymous `GET /wiki/IT:Ansible` now returns HTTP 200 with `<title>Login required - CTTB Wiki</title>` and a body containing one `ombox` table, one `Ambox_important.svg` reference, and the "Audience controlled" copy.

**Deleted as orphans** (via API `action=delete`):
- `MediaWiki:Accesscontrol-info` — old in-page notice (parser-tag handler is gone)
- `MediaWiki:Accesscontrol-info-box` — older variant of same
- `CTTB Wiki:Deny user` — AccessControl's full-deny page
- `CTTB Wiki:Deny anonymous` — AccessControl's anon-deny page
- `MediaWiki:Group-IT` — AccessControl group display message
- `IT` (NS_MAIN) — the AccessControl access list created during debugging
- `Test:AccessControl` — the smoke-test page from earlier session

Drafts kept in `.claude/wiki-pages/` for the three new messages so future edits go through `wikitools/wiki-edit.sh` rather than the wiki UI.

### Mbox border on Lockdown deny pages — TemplateStyles scoping fix

The "Login required" / `MediaWiki:Loginreqpagetext` page rendered the Ambox table classes correctly but with no border or background. Cause: Module:Message_box's TemplateStyles sheet scopes every selector to `.mw-parser-output .ombox{...}` (TemplateStyles' default isolation behavior — keeps article CSS from leaking site-wide). Special pages like `Special:Userlogin` don't wrap body content in `.mw-parser-output`, so none of those rules match. Same problem affects `MediaWiki:Badaccess-groups` and `MediaWiki:Badaccess-group0` when Lockdown surfaces them.

Fixed in `MediaWiki:Common.css` by re-stating the table border, background, and per-type accent colours unscoped (`table.ambox`, `.ambox-content`, etc.), plus the cell layout (`.mbox-image`, `.mbox-text`, `.mbox-empty-cell`) the parser-output-scoped sheet would otherwise supply. Stuck to upstream values — only the base border colour swaps `#a2a9b1` (almost invisible on white) for `var(--border-color-base, #c8ccd1)`.

Also tightened `MediaWiki:Loginreqpagetext` — dropped the "Members of the Administration would like to ask that you do not share this media" sentence since it doesn't make sense on a login prompt; it stays on `Badaccess-groups` where the visitor *has* logged in and is being denied membership-wise.

Verified anonymously: `GET /wiki/IT:Ansible` body now contains both the unscoped border declaration (`border-color:#f28500` for ambox-content) and the trimmed copy.

### Wiki: lock-prefix on restricted links + Special:Search 500 fix + MW 1.43.8

Two adjacent issues, both surfaced after the AccessControl→Lockdown migration:

**1. Lock-prefix on restricted links.** Added a `HtmlPageLinkRendererBegin` hook to the role's `LocalSettings.php.j2` that walks the link target's namespace, looks up `$wgNamespacePermissionLockdown[$ns]['read']`, intersects with the current user's effective groups, and — if the user is not in any allowed group — prepends `🔒 ` to the link text and stamps the anchor with `class="cttb-restricted-link"` plus a `title="Restricted: requires membership in <groups>"` tooltip. Handles all three text shapes the hook can receive (plain string, `null` fallback, `HtmlArmor`). `MediaWiki:Common.css` got matching muted-grey styling so locked links read as visually subdued. Verified end-to-end: `[[IT:Ansible]]` from a public page renders as `🔒 IT:Ansible` for anon, normal for IT-group members.

**2. `Special:Search` HTTP 500 (`PreconditionException`).** Every search query died on `RevisionStore::ensureRevisionRowMatchesPage` → `Title::getId()` → `assertProperPage()` ("This Title instance does not represent a proper page, but merely a link target."). Root cause in `includes/search/SqlSearchResultSet.php` (line ~60):

```php
$result = new SqlSearchResult(
    Title::makeTitle( $row->page_namespace, $row->page_title ),
    $terms
);
```

`Title::makeTitle()` returns a Title flagged as link-target-only; the new strict-mode `assertProperPage` check rejects every `getId()` call on it. Fixed via a one-line role-managed `replace` task that swaps `Title::makeTitle(...)` for `Title::newFromRow($row)`, which uses the page-table row to construct a proper page-bearing Title. Tagged `search-patch` so it can be re-applied after every MW upgrade. Verified: search for `splash` and `ansible` both return 200 with results lists.

**MW upgrade 1.43.1 → 1.43.8.** Initially attempted as a fix for the search bug (the precondition check was added in 1.43 and we hoped a patch fix had landed). It hadn't — the `makeTitle`-vs-`newFromRow` issue is still in 1.43.8 — but the upgrade was independently worth it (8 patch releases of bug fixes). Wrote `plays/wiki-upgrade-patch.yml`: stages a locally-downloaded tarball onto the container, extracts over the install with `--exclude=LocalSettings.php --exclude=images --exclude=cache`, re-extracts our extdist extensions on top (Lockdown / TemplateStyles, neither of which are in the core tarball), runs `update.php --quick`, and prints the new `MW_VERSION` for confirmation. Run with:

```
ansible-playbook plays/wiki-upgrade-patch.yml -l wiki-2404 -i inventory/hosts \
  --vault-password-file /tmp/vault-pw.sh \
  -e mw_upgrade_local_tarball=/tmp/mw_upgrade/mediawiki-1.43.8.tar.gz \
  -e mw_upgrade_target_version=1.43.8
```

Verified post-upgrade: Main_Page loads, Lockdown still enforces (`/wiki/IT:Ansible` → "Login required"), the lock-prefix hook still runs, the search patch survived (we re-applied via `--tags search-patch`).

### Wiki: lock-prefix per-user — parser-cache-safe two-pass design

The first cut at the lock-prefix link decorator computed visibility per user inside `HtmlPageLinkRendererBegin`, which runs at parse time. MediaWiki's parser cache is shared across users; whoever's render filled the cache decided what every other viewer saw. Result: the user reported the opposite of intended behavior — IT members saw 🔒 on links they could read, anon viewers saw clean links to pages they couldn't.

Refactored to a two-pass design:

**Pass 1 — at parse, identical for everyone (cache-safe).** `HtmlPageLinkRendererBegin` hook stamps every link to a Lockdown-protected namespace with:
- `class="cttb-restricted-link"`
- `data-restrict-groups="<space-list of allowed groups>"`
- `<span class="cttb-lock" aria-hidden="true">🔒 </span>` wrapping the prefix
- A `title` tooltip listing the required groups

The output is identical regardless of who triggered the parse, so cache hits are correct.

**Pass 2 — at render, per-request (uncached).** `OutputPageBodyAttributes` hook adds `cttb-user-in-<group>` body classes for each effective group of the current viewer (skipping pseudo-groups like `*` whose name strips to empty).

**CSS in `MediaWiki:Common.css`** — default state shows the lock and dims the link; group-keyed rules hide `.cttb-lock` and restore normal blue link colour when the body class matches one of the link's required groups. Five rules cover IT / DRBU / DVGS / DVBS / CTTB.

Verified: anon `GET /wiki/Main_Page` returns 5 `cttb-restricted-link` anchors and a body class with no `cttb-user-in-*` token. Logged-in IT viewer's render produces identical HTML but the body picks up `cttb-user-in-it`, hiding the locks and restoring normal styling via CSS.

---

## 2026-05-07 — firstlogin/welcome/migrate-home triage on dvgs-testmachine

**Symptom (reported by JC, terminal screenshot from a live session as `john.chandara@dvgs-testmachine`):**

```
$ sudhanix-migrate-home
sudhanix-migrate-home: must be run as root
$ sudhanix-firstlogin
$ sudhanix-welcome
[sudhanix-welcome] no cached PAM token; can't reach LDAP this session
```

Three failures look related; only one is real.

### Triage

**1. `sudhanix-migrate-home` "must be run as root" — by design.** `/usr/local/sbin/sudhanix-migrate-home` is the sysadmin-callable form. It guards on `id -u -ne 0` and exits 2. The user-side path is `/usr/local/sbin/sudhanix-firstlogin`, invoked synchronously by `/etc/X11/Xsession.d/55sudhanix-firstlogin` before xfce4-session forks. Source: `roles/sudhanix-core/files/firstlogin/sudhanix-migrate-home:25-29`. No code change.

**2. `sudhanix-firstlogin` silent — no bug; already-bootstrapped no-op path.** Live inspection of john.chandara's NFS home (`sudo -u john.chandara`, since NFSv4 root-squash maps server-side root reads to `nobody`):

- Marker present: `/nfs/home/john.chandara/.config/sudhanix/v26-bootstrapped` written `2026-05-07T15:30:05Z`, hostname `dvgs-testmachine.cttb`.
- Bootstrap log `~/.cache/sudhanix-firstlogin.log` shows the full successful run from the Xsession.d hook: `quarantined: .config/{xfce4,lxqt,openbox,plank}` → `~/.config/.pre-sudhanix-26.20260507-083005/`, `seeded from /etc/skel via rsync (ignore-existing)`, `wrote ~/.dmrc (Session=xfce)`, `marker written`.
- All four subsequent terminal invocations during the test session correctly reported `already bootstrapped (marker present); exit 0` to the per-user log and produced no stdout. That silence on stdout is the designed behavior for the autostart re-run path — see `roles/sudhanix-core/files/firstlogin/sudhanix-firstlogin-lib.sh:174` (`sfl_already_bootstrapped` returns true → log line + return). `~/.sudhanix-migration-NOTES.txt` was also written, confirming first-run success.

The 2026-05-06 first-login bootstrap implementation (last entry above) is **working** on this host. No code change.

**3. `sudhanix-welcome: no cached PAM token` — real bug.**

All scaffolding is correctly deployed on dvgs-testmachine:

| Asset | State |
|-------|-------|
| `/usr/local/sbin/sudhanix-cache-token` | 0755 root:root, deployed 2026-05-05 19:16 |
| `/usr/local/sbin/sudhanix-shred-token` | 0755 root:root, deployed 2026-05-05 19:16 |
| `/etc/tmpfiles.d/sudhanix-tokens.conf` | `d /run/sudhanix-tokens 1733 root root - -` |
| `/run/sudhanix-tokens/` | `drwx-wx-wt 2 root root` (matches tmpfiles.d) |
| `/etc/pam.d/lightdm` | `auth optional pam_exec.so expose_authtok /usr/local/sbin/sudhanix-cache-token` correctly inserted after `@include common-auth` |
| `/run/sudhanix-tokens/2156.tok` | **MISSING** for the just-completed session |

The hook is wired but the token file was never written. Cause is currently invisible: `pam_exec` was deployed without a `log=` option, so any stderr from the child script is dropped to `/dev/null`; `cache-pam-token.sh` itself has no internal logging and exits 0 from every failure branch (empty PAM_USER, empty stdin, mkdir fail, write fail). Four plausible root causes, ranked:

1. **`expose_authtok` not delivering PAM_AUTHTOK to stdin** — pam_exec EOFs immediately, `read -r PW` returns empty, script exits 0 silently. Could be Ubuntu 24.04 pam_exec semantics, the `pam_succeed_if.so user ingroup nopasswdlogin sufficient` line short-circuiting before AUTHTOK is set, or LDAP path consuming PAM_AUTHTOK differently from pam_unix.
2. **Auth stack short-circuited before the hook line** — `@include common-auth` resolves to `sufficient` somewhere and PAM stops. Should not happen given Ubuntu's stock common-auth ending in `pam_permit required`, but worth verifying.
3. **Hook fires, token written, then immediately shredded.** Unlikely — dir is empty, not "had a token then lost it."
4. **Login bypass** — auto-login or session-restore path that doesn't traverse the lightdm PAM stack. john.chandara is not in `nopasswdlogin`, so `pam_succeed_if` should not bypass.

### Fix (this session): instrument, then iterate

Two edits, scoped to the welcome role:

**`roles/sudhanix-core/files/welcome/cache-pam-token.sh`** — added unconditional logging to `/var/log/sudhanix-pam-cache.log` on every branch. Heartbeat at invocation logs `PAM_USER`, `PAM_TYPE`, `PAM_SERVICE`. Each early exit logs the reason (`empty PAM_USER`, `id -u produced no numeric uid`, `empty stdin (expose_authtok did not deliver token)`, `mkdir failed`, `write failed`). Success logs `wrote /run/sudhanix-tokens/<uid>.tok (N bytes)`. **PAM_AUTHTOK content is never logged — only its byte length on success.**

**`roles/sudhanix-core/tasks/sudhanix-welcome.yml`** — added `log=/var/log/sudhanix-pam-cache.log` to both `pam_exec` lineinfile entries (auth-cache + session-shred). Used `regexp:` so the existing line is *replaced* in `/etc/pam.d/lightdm` — `lineinfile` without a `regexp` would have appended a duplicate. The regexp tolerates the old (no `log=`) and new (with `log=`) forms so re-runs are idempotent.

### Side findings filed as GitHub issues, scope kept tight

- `moonexpr/monogarden#2` — Vajra 1.1.0 LDAP Debug fails with `Confidentiality required (13) — TLS confidentiality required` from `bundled/ldap_debug.lua:50`/`:72`. Lua `ctx:ldap_search` opens an unencrypted LDAP connection; campus OpenLDAP enforces ssf. Fix is in `app/vajra/src/lua_bridge.rs` — needs StartTLS or `ldaps://` before bind.
- `moonexpr/monogarden#3` — Vajra Quick Links pane renders six tiles instead of four: Wiki and Storehouse appear twice. `app/vajra/src/tools/quick_links.lua` bundles three (`Wiki`, `Storehouse`, `APT Repository`); `/etc/vajra/quick-links.json` operator override adds Wiki + Storehouse + Gateway; merge in the loader/UI is additive without dedup. Fix in `app/vajra/src/loader.rs` or `ui.rs`.
- `moonexpr/cttb-ansible#2` — Vajra "Set Hostname" pkexec dialog reads `Password for administrator:`, defaulting to the local Ansible-managed admin account rather than accepting an `it`-group LDAP user. No polkit rule grants `unix-group:it` `org.freedesktop.hostname1.set-hostname`. Existing pattern in `roles/sudhanix-core/files/config/10-network-manager.{pkla,rules}` should be cloned for hostname1.

### Deploy + verify (next iteration)

```bash
source utils/setup-env
ansible-playbook plays/install-sudhanix-cslabs.yml \
    --limit dvgs-testmachine --tags sudhanix_welcome --diff
```

Then log out + back in via lightdm, and check:

```bash
sudo tail -40 /var/log/sudhanix-pam-cache.log
sudo ls -la /run/sudhanix-tokens/
sudo -u john.chandara sudhanix-welcome
```

The log output picks the next branch on the decision tree. Expected outcomes:

- `invoked PAM_USER=john.chandara ... wrote /run/sudhanix-tokens/2156.tok (N bytes)` → original miss was a transient deploy state; recheck welcome app behavior.
- `invoked` then `exit: empty stdin (expose_authtok did not deliver token)` → root cause is auth-stack ordering; investigate where PAM_AUTHTOK is consumed before reaching the cache hook (likely either pam_unix re-prompt-on-fail before pam_ldap, or `pam_succeed_if` ordering).
- No log entries at all → hook never fires; investigate auth-stack short-circuit.
- `invoked` from an unexpected `PAM_SERVICE` → lineinfile landed in the wrong PAM file.

Plan and decision tree captured in `.claude/plans/inherited-prancing-bubble.md`.

---

## 2026-05-07 — BACKLOG → GitHub milestones migration

`BACKLOG.md` retired. Forward-looking work now lives in seven GitHub milestones with agent-pickup-style issues. Three labels capture the BACKLOG categories: `Blocker`, `Release`, `Unscheduled`.

Milestones: https://github.com/moonexpr/cttb-ansible/milestones

| # | Milestone | Issues |
|---|-----------|--------|
| 1 | P1 Autoinstaller | #8 (Blocker), #9, #10 |
| 2 | P2a Bootstrap & Migration | #11, #12, #13, #14, #15, #16, #17, #18, #19, #20, #21, #22 |
| 3 | P2b Vajra Multitool | #23 |
| 4 | P3a Release Documentation | #24, #25, #26 |
| 5 | P3b Release SysAdmin Manual | #27 |
| 6 | SP Wiki Upgrade | #28 |
| 7 | SP PXE Upgrade | #29 |
| — | Unmilestoned (NTH) | #30, #31, #32 |

### Completed during the upgrade (record from retired BACKLOG.md)

Captured here for posterity since the items contributed to the Sudhanix 26 release outcome.

**Infrastructure / install**

- Autoinstall hostname — fixed 2026-04-30 (common role `ansible.builtin.hostname` task)
- apt.cttb mirror missing Noble — sync started 2026-04-30, verified 2026-05-04 (noble + noble-security + noble-backports)
- Chrome GPG key expired — fixed 2026-04-30 (`trustedkeys.gpg` updated, mirror re-synced)
- No HTTPS egress from campus LAN — root cause: e2guardian `timed_internet.sh` cron schedule
- LDAP `nsswitch.conf` version guard — removed `== '20.04'` guard
- LightDM not set as default DM — task added to write `/etc/X11/default-display-manager`
- IPv6 disable sysctl — config deployed
- All playbook failures — resolved at run 17 (ok=144, changed=27, failed=0)
- WiFi on dvgs-lab3 — connected to DRBU via `nmcli` (2026-04-30)
- dvgs-testmachine unreachable after reboot — actual IP is `10.11.30.60` not `10.11.9.23`; reachable via direct SSH (2026-05-04)

**Desktop / UX**

- Wallpaper rotation — replaced cron+feh with `xfdesktop` native cycling (2026-05-01)
- Desktop icon text shadow — `show-icon-label-shadows` + Semi-Bold font (2026-05-01)
- WhiteSur tarballs uploaded — 2026-04-22
- Window snapping + center spawn — already in `xfwm4.xml.j2` (snap_to_border/windows, placement_mode=center) (2026-05-04)
- Terminal font size — 12 → 10pt in `terminalrc` (2026-05-04)
- Log Out menu entry — `cttb-signoff.desktop` above Sleep/Shutdown (2026-05-04)
- Log Out menu duplicate — excluded system `xfce4-session-logout.desktop` from top-level menu (2026-05-04)
- Thunar list view — `thunar.xml.j2` with `ThunarDetailsView` default (2026-05-04)
- Meta key → app menu — `xfce4-keyboard-shortcuts.xml.j2` (2026-05-04)
- Application search — `xfce4-appfinder` + Super+Space shortcut (2026-05-04)
- Greeter wallpaper — LightDM points to `Big-Sur-Day.jpg` (directory paths don't work) (2026-05-04)
- Greeter black background — `lightdm-gtk-greeter` needs file path not directory (2026-05-04)
- Greeter `[language_code]` — removed `~language` indicator (2026-05-04)
- Greeter macOS styling — WhiteSur-Dark theme + custom CSS, dark rounded login box (2026-05-04)
- Dark theme icons — switched `icon_theme` to WhiteSur-dark (2026-05-04)
- System sounds — bigsur theme installed from storehouse, enabled in xsettings (2026-05-04)
- 24-hour clock — panel clock format `%H:%M` (2026-05-04)
- Per-site wallpapers — unified to `Big-Sur-Day.jpg` across all sites (2026-05-04)
- Verify wallpapers deployed — Big-Sur-Day.jpg (10.8MB) in `/usr/share/backgrounds/cttb/`, 35 wallpapers, tarball on storehouse (2026-05-04)
- Panel in Plank dock — devilspie2 `skip_tasklist` rule (2026-05-04)
- Remote screenshot utility — `plays/util-screenshot.yml` (2026-05-04)
- Fonts/assets to storehouse — done, all assets use `ansible_assets_url` (2026-05-04)

**Apps**

- Chrome — apt install task added, `.desktop` filename fixed to `google-chrome.desktop` (2026-05-04)
- Chrome NFS lock — login script removes stale `SingletonLock` from other hostnames (2026-05-04)
- Chrome default browser — `xdg-settings` in `sw-browser.yml` (2026-05-04)
- Firefox — apt package with `install_recommends: no` (2026-05-04)
- Firefox snap blocker — resolved: apt `.deb`, not snap wrapper. Snap-store removed (2026-05-04)
- Zen Browser — Flatpak from Flathub (2026-05-04)
- Thunderbird proxy — campus proxy autoconfig pref deployed (2026-05-04)
- VSCode repo conflict — cleanup tasks for auto-generated `vscode.sources` + stale `.gpg` key (2026-05-04)
- Zoom .deb diagnosed — storehouse copy corrupted; fresh `.deb` from zoom.us valid; refresh of storehouse deferred to issue #18 (2026-05-04)

**Security / filtering**

- Revert dvgs-testmachine unrestricted filter — removed stale `10.11.9.23` from `adult` group; `ips: []` (2026-05-04)
- CA certs — CTTB Root CA at `/usr/local/share/ca-certificates/CTTB-Root-CA.crt`, symlinked in `/etc/ssl/certs/` (2026-05-04)

**System services**

- CUPS running — `lpstat -r` confirmed (2026-05-04)
- NFS mounts — autofs at `/nfs/home` (2026-05-04)
- WhiteSur-dark icon archive — `/usr/share/icons/WhiteSur-dark` deployed (2026-05-04)
- macOS sound theme sourced — bigsur tarball on storehouse (614KB), installed to `/usr/share/sounds/bigsur` (2026-05-04)

**Sudhanix branding (first pass, 2026-05-05)**

- `/etc/lsb-release` — `DISTRIB_ID=sudhanix`, `Sudhanix 26`, codename `storehouse` via `roles/common/templates/lsb-release.j2`
- `/etc/os-release` — `PRETTY_NAME="Sudhanix 26"`, `NAME=Sudhanix`, `HOME_URL` → wiki.cttb via `roles/common/templates/os-release.j2`
- MOTD `/etc/update-motd.d/00-header` — wiki.cttb primary, Ubuntu/XFCE secondary
- Disabled Ubuntu MOTD scripts (`10-help-text`, `50-motd-news`, `90-updates-available`, `91-release-upgrade`, `95-hwe-eol`)
- GRUB menu strings — `GRUB_DISTRIBUTOR` auto-resolves via `/etc/os-release` → "Sudhanix GNU/Linux"; added `GRUB_TIMEOUT_STYLE=menu` + `GRUB_TIMEOUT=3`
- Plymouth boot splash — Sudhanix theme deployed (lotus PNG, macOS-style script with progress bar, registered via `update-alternatives`, baked into initrd; required `quiet splash` in `GRUB_CMDLINE_LINUX_DEFAULT`)
- Ansible role rename — `desktop` → `sudhanix-core`, `desktop-distributed` → `sudhanix-distributed`, `ux.yml` → `sudhanix-ux.yml`
- Playbook rename — `cs-lab-2404.yml` → `install-sudhanix-cslabs.yml`

**Wiki documentation**

- 31 articles fully prose-passed in lecture-notes voice (rounds 1-8, 2026-05-06).
- Test/Test1 sandbox pages deleted (2026-05-06).
- HelpfulWebSitesForContentFiltering merged into Content Filtering FAQ; old title now redirects (2026-05-06).
- Remaining wiki work tracked in #24, #25, #26.

---

## 2026-05-07 — vajra port-rest-of-legacy-tools, two test cycles, ldap_group_ou fix

Two-pass dev/test cycle on dvgs-testmachine for the Rust+Lua vajra rewrite. End state: vajra 1.2.1-1 installed, all 22 bundled tools loaded (19 newly ported in this branch + 3 previously bundled).

### Branch rename

`feature/ubuntu22-upgrade` → `release/sudhanix26` on `origin` (GitHub). Internal `cttb` remote pushed once on-campus. The old name predated the noble target; the new one names what's actually shipping.

### vajra source: 19 tools ported, framework upgrade (moonexpr/monogarden#4, vajra 1.1.0 → 1.1.1 → 1.2.1)

19 legacy Python tools translated to Lua under `app/vajra/src/tools/` and registered in `loader.rs::BUNDLED`:
`app_install`, `apt_updates`, `cache_flush`, `chrome_locks`, `device_register`, `display`, `firewall`, `hardware`, `kerberos`, `network_diag`, `password_reset`, `print_queue`, `services`, `sessions`, `storage`, `sudhanix`, `time_ntp`, `wakeonlan`, `welcome_reset`, `xfce_reset`.

Framework upgrade: `ctx:run` and `ctx:run_privileged` now accept an optional opts table (`env`, `timeout`, `input`, `check`). For privileged calls the env is wrapped via `pkexec ... env VAR=val ...` because pkexec strips its child env — apt-style ports rely on `DEBIAN_FRONTEND=noninteractive` and friends.

Two side bugs fixed in the same PR:

- **moonexpr/monogarden#2 — LDAP TLS.** Campus OpenLDAP enforces `olcSecurity ssf>=128`; vajra was issuing cleartext binds and getting `Confidentiality required (13)`. `ldap_search` now adds `-ZZ` for `ldap://` URIs and threads optional `tls_cacert` through `LDAPTLS_CACERT` via a new `merged_env` helper that preserves PATH/HOME so `env_clear` doesn't break ldapsearch. Second pass extended `-ZZ` to `welcome_reset` (ldapmodify) and `password_reset` (ldappasswd) — same campus refusal, same fix.
- **moonexpr/monogarden#3 — Quick Links dedup.** Operator override at `/etc/vajra/quick-links.json` was being appended to the bundled list without dedup; lab hosts saw 6 tiles (Wiki, Storehouse twice; APT Repository; Wiki, Storehouse from override; Gateway). `links_view` now seeds a `HashSet` of bundled URLs and skips overrides that collide. Policy documented inline: append + dedup by URL; ship a system drop-in to fully replace.

### First test cycle — found two GUI defects + one infrastructure blocker

Built and verified mechanically on dvgs-testmachine via `cttb-ansible/plays/test-vajra-pr.yml` (new). Build clean, binary contains the new tool IDs, `ldapsearch -x -ZZ -LLL -H ldap://ldap-srv.cttb` works against the campus LDAP standalone — confirms the StartTLS fix mechanism.

Pool deployment was the original target. Discovered the apt.cttb pool layout (debmirror LXD container hosted on srv-nas, reprepro at `/srv/cttb-repos/apt/ubuntu/`, public URL `http://apt.cttb/cttb-repos/apt/ubuntu`, Apache + symlink, no nginx). Adding a `noble` distribution worked; signing failed because the cttb-repo signing key (`C77F25EB89F06C01`) is passphrase-protected and gpg 1.4.20 on the container has no batch-mode access path — filed as cttb-ansible#5. Fell back to direct `dpkg -i` for the test deploy.

GUI testing then surfaced two bugs that the mechanical pass couldn't catch:

- **moonexpr/monogarden#6 — Plymouth wedge.** `Sudhanix → Plymouth boot screen test` ran the recipe `plymouthd --mode=boot && plymouth show-splash && sleep 10 && plymouth quit --retain-splash; plymouth quit` (faithful Python port). On a live X session this attaches plymouthd to the same DRM/framebuffer, layers above X's draw surface, and `--retain-splash` explicitly keeps the splash on the framebuffer when plymouthd exits — desktop went black, power-off / logout dialogs never repainted, hard power-cycle required. Replaced with `plymouth_status`: read-only — prints active theme, available themes, and unit state.
- `Sudhanix → System information` launched gnome-system-monitor instead of showing data inline (faithful port; user expectation mismatch). Replaced with `show_sysinfo`: prints host/OS/kernel/CPU/RAM/uptime in the result body, full `lscpu`/`free -h`/`df -h`/`lsblk`/`ip -br addr` in details. No external app launched.

Also filed during the test pass:

- **moonexpr/monogarden#5 — vajra has no headless invocation path.** Testing #2 and #3 acceptance had to be a human-clicking-buttons exercise. Proposed: `vajra tools list / run / status` and `vajra lua -e ...` CLI mode reusing the existing `AppContext` and `LuaEngine`. Future test passes can then run as ansible playbooks against real `ActionResult` JSON, not just `strings | grep` heuristics.

### Second test cycle — operator delivered an 8-page PDF report → vajra 1.2.1

Test report covered the 1.1.1 deploy. New bugs:

- **moonexpr/monogarden#10 — `ldap_debug` "List my LDAP groups" failed with `No such object (32)` matched at `dc=cttb`.** Root cause: campus directory exposes `ou=Groups,dc=cttb` (plural) but vajra's bundled fallback (`context.rs::ldap_cfg`), the `.deb`-shipped `packaging/ldap.json`, and the `roles/sudhanix-vajra-tool/defaults/main.yml::vajra_ldap_group_ou` all used `ou=Group,dc=cttb` (singular). Typo carried since the original Python era. Fixed in all three places. Hosts that already had `/etc/vajra/ldap.json` deployed needed a conffile update (dpkg flagged the file as operator-modified because the ansible role had written the singular default; resolved with `dpkg --force-confnew -i`).
- **moonexpr/monogarden#11 — `xfce_reset` lockout.** Action quarantined the user's XFCE config and printed `(skipped: /usr/local/sbin/sudhanix-firstlogin not found)` when the bootstrap binary was absent — leaving the user unable to start a session next login ("Unable to load a failsafe session — xfconfd isn't running, $XDG_CONFIG_DIRS, etc."). Action now refuses pre-flight if the binary is missing.
- **moonexpr/monogarden#12 — Sudhanix `open_welcome` false success.** Reported "Welcome panel launched" without verifying the binary exists or that `spawn()` didn't raise. Now pre-checks `/usr/local/bin/sudhanix-welcome` with `test -f` and wraps spawn in `pcall`.

Structural change:

- Standalone `set_hostname.lua` tool removed. The same action lives inside the Sudhanix tool's `set_hostname` runner; the duplicate sidebar entry was operator confusion noted in the report.

UX requests filed for follow-up cycles (not implemented this PR):

- **moonexpr/monogarden#8 — sidebar typing-to-search.** Spotlight-style: typing with no field focused opens a search bar and filters the tool list by label + description. Skip if a form input has focus. Esc clears.
- **moonexpr/monogarden#9 — Quick Links to top-of-sidebar widget.** Move the link grid out of the dedicated category into a compact tile row at the top of the sidebar; hover shows the destination URL; badge styling. Retire the standalone Quick Links category.

### Ansible role changes (this branch, `release/sudhanix26`)

- **`roles/sudhanix-vajra-tool/defaults/main.yml`:** `vajra_ldap_group_ou` default → `ou=Groups,{{ vajra_ldap_base_dn }}` (was `ou=Group`). On next role run, deployed `/etc/vajra/ldap.json` will be rewritten to match.
- **`plays/test-vajra-pr.yml` (new):** rsync local `app/vajra/` to dvgs-testmachine; install build deps + rustup; `cargo build --release`; lua syntax-check every bundled tool; verify `ldapsearch -ZZ` against campus LDAP. Used to validate moonexpr/monogarden#4 end-to-end without touching the apt.cttb pool.
- **`plays/publish-vajra-deb.yml` (new, blocked):** three-act flow: build the .deb on testmachine, synchronize to srv-nas, lxc file push into the debmirror container, reprepro includedeb + export against a noble distribution, then add a cttb-repos apt source on testmachine and apt install. Currently parked at the noble-distribution step because of the signing-key blocker (cttb-ansible#5). Committed so the structure is in tree for when that decision lands.

### Deploy state on dvgs-testmachine

vajra 1.2.1-1 installed via direct `dpkg --force-confnew -i`, not via apt.cttb pool. `/etc/vajra/ldap.json` corrected to `ou=Groups,dc=cttb`. `/usr/local/lib/vajra/tools/sudhanix.lua` drop-in (used to test the sysinfo + plymouth replacements before the .deb rebuild) removed; bundled tool from the .deb is now what runs. Binary contains `-ZZ`, `ou=Groups,dc=cttb`, and "Refusing to reset" — verified via `strings`.

Next test pass should verify GUI behaviour of: LDAP groups list (now plural), Reset Welcome Dismissal, Reset Password (write paths' StartTLS), `xfce_reset` refusal on this host (no firstlogin binary), `open_welcome` reporting an error when binary absent, System information showing CPU/RAM/disk inline, Plymouth status read-only.

---

## 2026-05-07 — xfce4-session.xml hot fix + plymouth Amitabha + Vajra Testing tools

Three follow-on landings from the morning's welcome-PAM-token session.

### xfce4-session "Unable to load failsafe" — root cause and hot fix

**Symptom (mid-session, JC at the seat).** After authenticating to lightdm successfully, the user lands on a modal `Unable to load a failsafe session` dialog. xfce4-session never reaches the desktop; the wallpaper paints behind the dialog.

**Root cause.** Ubuntu 24.04's `xfce4-session` package installs `/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml` as a placeholder where every property is `type="empty"`:

```xml
<property name="general" type="empty">
  <property name="FailsafeSessionName" type="empty"/>
  <property name="SessionName" type="string" value="Default"/>
</property>
<property name="sessions" type="empty">
  <property name="Failsafe" type="empty">
    <property name="Client0_Command" type="empty"/>
    ...
```

`SessionName="Default"` references a `Default` block that doesn't exist; falls back to Failsafe; Failsafe has no Client commands set. xfce4-session aborts with the dialog. JC's morning session worked only because xfce4-session loaded an autosaved session-cache from `/tmp/.unburden-john.chandara/cache/sessions/`. After log-out the cache rotated empty; the next login had nothing to fall back to and the empty placeholder bit.

**Hot fix on dvgs-testmachine.** Wrote a working `xfce4-session.xml` at `/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml` with `FailsafeSessionName=Failsafe`, `SessionName=Failsafe`, and a populated Failsafe block listing five clients (`xfwm4`, `xfsettingsd`, `xfce4-panel`, `Thunar --daemon`, `xfdesktop`). Backed up the upstream broken file to `*.upstream-broken`. After the fix lands, lightdm authentication produces a working desktop on first login. Quarantine interaction note: a previous session attempt had a per-user override at `~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml`; running the firstlogin "quarantine hot fix tool" (which forces re-quarantine by removing the marker) moved that file into `~/.config/.pre-sudhanix-26.<ts>/`, which is why the dialog returned mid-session. Lesson for the firstlogin script: per-user xfconf XMLs should not be quarantined as part of the "stale config" sweep — they're the autosaved state and forward-compatible.

**Codification (todo).** Drop `roles/sudhanix-core/files/config/xfce4-session.xml` with the working content; add a copy task in `lookandfeel.yml` that lays it down at `/etc/xdg/...` mode `0644 root:root`, tagged `desktop`. Until that lands, future PXE-installed hosts will hit the same dialog on first LDAP-user login. cttb-ansible#7 captures the full punch list.

### Plymouth: lotus.png → amitabha.png

Previous boot splash used a hyper-realistic 1024×1024 lotus that read more uncanny than calming. Swapped to a stylised Amitabha figure that reads cleanly at boot resolution and matches the calmer monastery branding. Repo changes: deleted `roles/sudhanix-core/files/plymouth/sudhanix/lotus.png`, added `amitabha.png`, updated `sudhanix.script`'s `Image()` reference and the `.plymouth` Description.

Hot-deployed to dvgs-testmachine via scp + `update-initramfs -u`. The role's `install Sudhanix Plymouth theme` task is gated on `creates: /usr/share/plymouth/themes/sudhanix`, so already-installed lab hosts will continue to render the old lotus until the storehouse tarball is rebuilt and re-uploaded, or the install task is reworked to detect file-level drift.

### Vajra Testing tool category (drop-in Lua, deployed via sudhanix-vajra-tool)

Per monogarden#7. Four Lua tool files dropped at `roles/sudhanix-vajra-tool/files/tools/`:

- `test_pam_auth.lua` — drives `pamtester` via `ctx:run_privileged` with the password piped on stdin; surfaces rc + cache-log tail + token-dir state.
- `test_token_state.lua` — `stat` metadata + uid-scoped log grep (token contents never displayed); "Clear my token" via privileged rm.
- `test_welcome_preview.lua` — three buttons: spawn welcome with `SUDHANIX_WELCOME_FORCE=1`; reset `sudhanixWelcomeDismissed` via cached-token `ldapmodify`; composite "Reset + show".
- `test_ldap_dismissal.lua` — read/set/clear the dismissal flag for any uid (anonymous-bind read; cached-token `ldapmodify` for writes; `sudhanixUser` aux objectClass added when needed).

All four declare `category = "Testing"`, `required_groups = { "it" }`, and use only the `ctx:` API surface verified in `app/vajra/src/lua_bridge.rs` (`run`, `run_privileged`, `spawn`, `ldap_search`, `ldap_escape`, `my_ldap_dn`, `config`, `has`). Deploy task wired into `roles/sudhanix-vajra-tool/tasks/main.yml` under tag `vajra-testing`. Lab-desktop counterpart to `utils/run-pam-test`; closes the iteration loop for IT staff doing per-host PAM/welcome QA from the GUI. Two known dependencies, surfaced in tool-level comments: monogarden#2 (Vajra LDAP TLS) and the missing `SUDHANIX_WELCOME_FORCE` env-var bypass in `/usr/local/bin/sudhanix-welcome`.

### Test harness usage during the session

`utils/run-pam-test dvgs-testmachine.cttb john.chandara` (cttb-ansible#3 Tier-1) confirmed the PAM stack reaches the cache hook, `expose_authtok` delivers PAM_AUTHTOK, and the script writes `/run/sudhanix-tokens/2156.tok` correctly chown'd. JC's earlier real lightdm login at 09:56:09 also reached the hook (per `/var/log/sudhanix-pam-cache.log`) but failed with EACCES on overwriting an existing user-owned token file — likely AppArmor mediation on the lightdm pam_exec child. Atomic mktemp+rename fix outlined in cttb-ansible#7. The harness also surfaced the shred-on-open hypothesis: `pam_exec.so` on the session line runs for both `open_session` and `close_session`, so without a `$PAM_TYPE` gate, shred fires immediately after auth-cache and wipes the token before xfdesktop autostart kicks in.

### Codification follow-up — xfce4-session.xml.j2

After the noon test, dropped the codified fix into the role. Surprise: `roles/sudhanix-core/templates/xfce4-session.xml.j2` was *already deploying* the broken upstream placeholder — captured verbatim from a working dvgs-testmachine on 2026-05-06 with a comment noting the empty Failsafe entries were "kept verbatim so xfce4-session doesn't substitute its own (potentially stale) factory set." That assumption was wrong; the empty entries are exactly what triggers the failsafe-determination failure when no autosaved cache exists. So the role itself was the source of the bug after every Ansible run, not just a fresh PXE install.

Replaced the template with a populated Failsafe definition (five clients: xfwm4, xfsettingsd, xfce4-panel, Thunar --daemon, xfdesktop) and forced SessionName="Failsafe". The existing `configure xfce4-session (SaveOnExit, default session)` task in `sudhanix-ux.yml` already deploys this template — no Ansible-task change needed. Verified end-to-end on dvgs-testmachine: `ansible-playbook plays/install-sudhanix-cslabs.yml --limit dvgs-testmachine.cttb --tags config --diff` produced ok=35 changed=1 with the diff cleanly transitioning the deployed file from empty-placeholder to populated. Tagged via `config` because lookandfeel.yml's tasks inherit that tag from the `setup/default.yml` include — `--tags sudhanix-core` does *not* deploy these (caught during the codification deploy).

Also caught while codifying: my Vajra Testing tool drop from earlier in the session (monogarden#7) was never actually committed — only the journal mention. Committed the four `test_*.lua` files and the deploy task in `roles/sudhanix-vajra-tool/tasks/main.yml` together with the xfce4-session fix, under tag `vajra-testing`.

Pending follow-ups in cttb-ansible#7: cache-token atomic mktemp+rename for the EACCES path, shred-token gate to close_session only with diagnostic logging.

---

## 2026-05-08 — Blocker sweep: cache-token atomic write, welcome FORCE bypass, plank dconf seed (closes #7, #35)

Both open Blocker labels cleared today against dvgs-testmachine via the unattended pamtester harness. No at-the-seat work needed.

### #7 cache-pam-token: atomic mktemp+rename

Replaced the bash `> "$TOKEN"` redirect with `mktemp -p "$DIR" ".${UID_NUM}.tok.XXXXXX"` followed by chmod / write / chown / `mv -f`. The pre-existing user-owned token file is never opened-for-write by root in lightdm's pam_exec child; instead a fresh root-owned tmpfile is written, chowned to the target user, and atomically renamed over the destination. Fail-soft: any step failure logs and `rm -f`'s the tmp.

Empirical proof on dvgs-testmachine: pre-staged a stale `/run/sudhanix-tokens/2156.tok` (10 bytes "STALEDATA" owned by `john.chandara:2156` mode 0600), then drove the auth phase via `printf '%s\n' "$PW" | sudo -n pamtester lightdm john.chandara authenticate`. Result: `wrote /run/sudhanix-tokens/2156.tok (10 bytes)` in the cache log, token re-owned correctly, no leftover `.2156.tok.XXX` tmpfile. The bash > truncate path that JC's 09:56:09 real-login hit yesterday is gone.

### #7 shred-pam-token: close_session gate (already in tree)

Verified on disk; the close_session gate landed yesterday afternoon (commit 36461ea1 era). Ran the open_session→close_session pair against pamtester to confirm the diagnostic logging:

```
[shred] invoked PAM_TYPE=open_session ... skip: not close_session
[shred] invoked PAM_TYPE=close_session ... shredded /run/sudhanix-tokens/2156.tok
```

Hypothesis #3 from cttb-ansible#7 — shred-on-open wiping tokens immediately after auth-cache wrote them — is empirically dead.

### #7 sudhanix-welcome: SUDHANIX_WELCOME_FORCE bypass

Added an env-var bypass at the top of `main()`. When `SUDHANIX_WELCOME_FORCE=1`, the LDAP token read and the `already_dismissed()` gate are skipped, so the panel renders unconditionally. The Continue button still records `sudhanixWelcomeDismissed` only when force is *off* — preview from vajra's `test_welcome_preview.lua` no longer side-effects the user's LDAP entry. Closes the missing-bypass dependency listed in monogarden#7.

### #35 firstlogin: seed user-db dconf for Plank

Generic helper `sfl_seed_user_dconf` walks `/etc/sudhanix/dconf-seeds/*.txt`, parses a `# prefix: /net/launchpad/plank/` directive line, and feeds the rest to `dconf load <prefix>`. Falls back to `dbus-run-session` when `DBUS_SESSION_BUS_ADDRESS` is unset (Xsession.d/40x11-common_xsessionrc normally exports it before our hook runs, but the wrapper makes the helper also work from migrate-home and CI). Logs each seed to firstlogin.log + the user-visible NOTES file.

Wired into `sfl_run_bootstrap` between `sfl_seed_from_skel` and `sfl_set_xfce_session_pref`. Deployed via `roles/sudhanix-core/tasks/sudhanix-firstlogin.yml` with a new `with_fileglob` over `firstlogin/dconf-seeds/*.txt` — drop a new `.txt` next to `plank.txt` and it deploys without YAML changes.

The trade-off the issue calls out is loud in the lib-script comment header: once the user-db is seeded, future updates to `/etc/dconf/db/site.d/00-plank-dock1` will NOT propagate (user-db beats system-db:site in the dconf profile). Re-seeding a fleet post-rollout requires either (a) bumping `SUDHANIX_VERSION` to re-quarantine, or (b) a separate `sudhanix-reseed-dock` sysadmin tool. We accepted lock-in vs. Plank's first-run auto-detect clobber; (b) is filed for a future agent.

Empirical proof: `dbus-run-session -- bash -c '. /usr/local/lib/sudhanix-firstlogin-lib.sh; sfl_seed_user_dconf'` against a synthetic `$HOME` returned the canonical 10-item dock-items list on `dconf read /net/launchpad/plank/docks/dock1/dock-items`. A second call from the same session was idempotent — same value, no spurious diff.

### Login harness verified end-to-end

`utils/run-pam-test dvgs-testmachine.cttb john.chandara` driven through `expect` (to satisfy its `read </dev/tty`) authenticated cleanly with the password sourced from Keychain, log tail confirmed `wrote /run/sudhanix-tokens/2156.tok (10 bytes)`, and the token persisted with correct ownership. Tier-1 of cttb-ansible#3 is live.

---

## 2026-05-08 (afternoon) — welcome panel rebuild + Plank auto-pinning fix (closes #51, #3, redoes #35)

What started as a "wire up the stubbed welcome screen" issue (cttb-ansible#51) turned into the day where the dock layout finally stops fighting back. The work touches the welcome panel, the Plank dock, the dconf seed pipeline, the WhiteSur theme casing, the vajra sidebar, and (eventually) the system-db site default that was the actual problem all along.

### #51 — welcome sidebar wired to Gtk.Stack

Replaced the decorative ListBox + dialog popups with a real `Gtk.Stack` content router. Five named pages: `welcome`, `whats-new`, `quick-tour`, `customization`, `about`. Sidebar `ListBox` row-selection drives `stack.set_visible_child_name()`. The bottom pill buttons go away — Customization and About are first-class sidebar entries now. The Continue button + "skip on next sign-in" checkbox move out of the welcome page into a persistent action row at the bottom of the right pane, reachable from any selected page.

CustomizationDialog and AboutDialog become `CustomizationPage(Gtk.Box)` and `AboutPage(Gtk.Box)`. Customization's Cancel button drops (no modal to cancel from); Apply gets inline "Applied" feedback for 2s.

What's new + Quick tour pages get provisional content sourced from `wiki.cttb / Sudhanix 26 Release Notes` and `Common Tasks on Sudhanix`: 2x2 takeaway-card grids, four cards per page, each with a 44px theme-neutral SVG line-art icon at `#7a7a7a` stroke — readable on both DARK and LIGHT panel CSS without per-theme variants. Eight new SVGs land at `/usr/share/sudhanix/welcome-icons/`.

Sidebar gets a macOS-Finder treatment: 16px icon next to each label, solid `#0a84ff` system-blue selected row with bold white text, tighter `4px 8px` padding. Five sidebar SVGs (`sidebar-house`, `-sparkle`, `-compass`, `-gear`, `-info`).

About row "User Guide" links to a new wiki stub at `[[Sudhanix User Guide]]` — published today as a directory-of-links to Migrating, Release Notes, Common Tasks. Replaces the "being drafted right now" placeholder.

### Live theme swap (DARK / LIGHT) plus xfwm4 alignment

Added a `GTK_CSS_LIGHT` mirror of the existing `GTK_CSS_DARK`. `apply_css_safe(theme)` is now hot-swappable — drops the prior provider before adding the new one, otherwise dark colours bleed through light. Clicking Light/Dark on the segmented control re-applies the welcome panel's own CSS in place; Apply additionally pushes the system theme to xfconf as before.

`apply_settings` now writes three xfconf knobs (`/Net/ThemeName`, `/Net/IconThemeName`, and `xfwm4 /general/theme`) on every theme switch, so window decorations follow the GTK widget theme. Same pattern in vajra's new `theme.lua` tool.

### WhiteSur theme casing standardized

The upstream tarballs ship inconsistently-cased dirs: GTK has `WhiteSur` (light) + `WhiteSur-Dark` (capital D); icons have lowercase `WhiteSur-light` + `WhiteSur-dark`. Setting the GTK theme to a non-existent name (we'd been using "WhiteSur-Light" everywhere) silently falls back to Adwaita, which is why the welcome panel's preview matched but the rest of the desktop did not.

Fix landed in `lookandfeel.yml`: bidirectional symlinks (`WhiteSur-light` and `WhiteSur-Light` → `WhiteSur`, `WhiteSur-dark` → `WhiteSur-Dark`, plus capital aliases for icons) so any tool can use either casing and resolve to the same backing dir. THEME_MAP and vajra theme.lua use the real-dir names so they always work even without the symlinks.

### Dock model: weighted anchors + four named categories

Replace the ad-hoc DOCK_GROUPS / DOCK_ALWAYS_PINNED constants with four named categories — `essentials` (always-on), `office`, `code`, `art` — backed by dconf-seeded metadata at `/org/sudhanix/dock/categories/<name>/`. Sysadmins or per-host overrides can change category contents without touching the welcome script.

Switched from a positional `{left, right}` anchors model to a single weighted number-space:

```
appfinder    weight    0   leftmost anchor
essentials   weight  100   always-on category
office       weight  300
code         weight  500   center
art          weight  700
trash        weight 1000   rightmost anchor
```

apply_settings sorts every contributing group by weight and concatenates in declared order, dropping anything not present in `~/.config/plank/dock1/launchers/`. Anchors only join the sort when at least one category contributes items — toggling everything off yields a blank dock by design.

`Trash.dockitem` (`Launcher=trash://`) drops into `/etc/skel/.config/plank/dock1/launchers/` so fresh users get the right anchor. The lookandfeel `setup default account files` task got extra tags (`config / install / lookandfeel / skel`) so `--tags lookandfeel` actually deploys the etc-skel tree — previously it only fired under `--tags sudhanix-core` which doesn't trigger the include itself.

### customize.yml — three constants become one declarative spec

Pulled THEME_MAP, BROWSER_MAP, and dock category metadata out of hardcoded Python constants into a single declarative `/usr/share/sudhanix/welcome/customize.yml`. The welcome script reads it at module load and populates theme presets, browser presets, and the dock category fallback from it. Embedded constants survive as a tertiary fallback.

Resolution order:
- Themes / browsers: customize.yml → embedded fallback
- Dock categories: dconf user-db → customize.yml → embedded fallback

CustomizationPage builds its theme segmented control, browser radio buttons, and dock chips dynamically from these data sources. Adding a theme or browser is a one-line YAML edit; sysadmins can template customize.yml per-school via Ansible.

### Dismiss-without-Apply default-everything

WelcomeWindow tracks `applied_during_session`. CustomizationPage._on_apply sets it on the parent. `_on_continue` (Continue button) and `_on_destroy` (window X-close) both check the flag — if Apply was never clicked, call `_apply_default_layout` which enables every non-always-on category plus the default theme and browser. So a user who never touches Customization ends up with the full dock by default rather than an empty one.

### The actual root fix — Plank's auto-pinning

We spent most of the day patching the symptoms of a single setting. Plank's `auto-pinning` defaults to true: any recently-launched app gets silently promoted to a permanent launcher. Plank writes a `.dockitem` file to `~/.config/plank/dock1/launchers/`, appends the app id to `dock-items` in user-db, and on every restart re-asserts the auto-detected list — undoing whatever the welcome panel just wrote.

That is what JC's session was hitting: every Plank restart would re-clobber dock-items with `app.zen_browser.zen-1.dockitem`, `vlc-1.dockitem`, `ktelnetservice5.dockitem`, etc. — apps Plank had silently auto-pinned across past sessions. apply_settings would write 11 items, Plank would over-write them, and the loop continued.

Two settings landed in `/etc/dconf/db/site.d/00-plank-dock1`:

```
auto-pinning = false   # no silent auto-promotion
pinned-only  = true    # only items in dock-items render
```

With those flipped, Plank only renders what `dock-items` lists, only writes `.dockitem` files when a user explicitly right-clicks "Keep in Dock", and apply_settings becomes the durable source of truth.

### Post-fix simplification

Now that auto-pinning is off, the empty-and-autohidden initial state machinery is load-bearing for nothing — stripped. Site default and `plank.txt` seed both ship the canonical 11-item weighted layout from minute one, with `hide-mode='none'`. A user who never opens welcome still gets the canonical dock; a user who opens it can narrow / expand / reorder.

Verbose apply tracing trimmed back to one-line summaries (kept `refresh_plank_skel: seeded=N pruned=N`, `apply theme=... browser=... dock={...}`, `dock-items rewritten: N items`, error-only branches). The defensive `refresh_plank_skel` prune logic stays for already-corrupted homes but is no longer the main line of defence.

### vajra: theme tool + Sudhanix-specific drop-ins

New Lua tool `theme.lua` for the vajra sidebar: status rows for GTK theme / Light-or-Dark / icon theme / cursor theme / xfwm4 window decorations / Plank dock theme / wallpaper, plus full-report and Light/Dark switch actions. Bundled in `vajra::loader::BUNDLED` for the next .deb release; deployed today as a runtime drop-in via the `sudhanix-vajra-tool` role under `vajra-config` so it shows up immediately.

The role's drop-in deploy section was reorganised: `sudhanix.lua`, `welcome_reset.lua` (sidebar Sudhanix tools), and `theme.lua` (sidebar System tool) now ship as Sudhanix-specific runtime tools alongside the four `test_*.lua` Testing-category tools, keeping vajra's upstream package portable.

### #3 login harness, end-to-end across the deploy

`utils/run-pam-test` driven via `expect` against the freshly-deployed binary on dvgs-testmachine:

```
auth          → pamtester: successfully authenticated; wrote /run/sudhanix-tokens/2156.tok (10 bytes)
open_session  → [shred] invoked PAM_TYPE=open_session ... skip: not close_session
ldapsearch -y → returns JC's entry; sudhanixWelcomeDismissed not present (welcome would render)
close_session → [shred] shredded /run/sudhanix-tokens/2156.tok
welcome FORCE → start pid=... uid=2156 force=True; refresh_plank_skel: seeded=11 pruned=0 ([])
```

Five-Apply smoke under JC's session driver: T1 (office only) → 9 items; T2 (all categories) → 11; T3 (all chips off) → 6 (essentials + anchors); T4 (simulated dismiss-default) → 11; restore → 9. Every Apply rewrites dock-items in dconf with `rc=0`, `launchers/` stays at exactly the 11 canonical files, `auto-pinning=false` blocks any re-auto-detect.

### Files touched

```
roles/sudhanix-core/files/welcome/sudhanix-welcome           +700 line refactor
roles/sudhanix-core/files/welcome/customize.yml              new — declarative spec
roles/sudhanix-core/files/welcome/icons/sidebar-*.svg        5 new sidebar icons
roles/sudhanix-core/files/welcome/icons/{lotus-menu,
  spotlight, dock, snap-package, keyboard, tile-windows,
  folder-split, screenshot, cloud-home}.svg                  9 new content-card icons
roles/sudhanix-core/files/dconf-db/00-plank-dock1            site default — auto-pinning fix
roles/sudhanix-core/files/firstlogin/dconf-seeds/dock-{
  essentials, office, code, art }.txt                        new — category metadata
roles/sudhanix-core/files/firstlogin/dconf-seeds/plank.txt   day-1 dock + auto-pinning
roles/sudhanix-core/files/firstlogin/sudhanix-fix-dock       per-user remediation tool
roles/sudhanix-core/files/config/etc-skel/.config/plank/
  dock1/launchers/Trash.dockitem                             new — right-anchor
roles/sudhanix-core/tasks/lookandfeel.yml                    bidirectional theme symlinks
roles/sudhanix-core/tasks/sudhanix-welcome.yml               customize.yml + icons + Trash
roles/sudhanix-vajra-tool/files/tools/theme.lua              new vajra tool
roles/sudhanix-vajra-tool/tasks/main.yml                     drop-in re-org

monogarden:
  app/vajra/src/tools/theme.lua                              new bundled tool
  app/vajra/src/loader.rs                                    BUNDLED entry

wiki:
  Sudhanix User Guide                                        new stub
```

Closes cttb-ansible#51, cttb-ansible#3. Re-validates cttb-ansible#35 (the empty-user-db preseed approach still works; the auto-pinning fix is the more complete answer).

## 2026-05-09 (evening) — Sudhanix 26 release drain: signed apt (#42), GRUB EFI (#8), watchdog (#34), vajra 1.0 (#38), full testmachine deploy, wiki batch publish (#46)

Automated backlog drain targeting the Sudhanix 26 milestone. All three open bugfix worktrees were merged into `release/sudhanix26`, a full end-to-end deploy ran against `dvgs-testmachine`, vajra was promoted to 1.0 stable, and 50 wiki pages were batch-published.

### #42 + #39 — signed apt releases

Root cause: reprepro on the `debmirror` LXD container (srv-nas 10.11.1.5) runs as root, but the only GPG key in root's keyring required a passphrase, and `ask-passphrase` in the reprepro options triggered a terminal prompt that doesn't exist in batch runs.

Fix: generated a new passphrase-less signing key as root using GPG 2.1.11's `%no-protection` batch mode (fingerprint B4A1DB48, uid "CTTB Repo Signing"). Removed `ask-passphrase` and the old `SignWith` stanza from reprepro options; `distributions` now carries `SignWith: B4A1DB48`. All existing noble packages re-included and the new key verified via `gpg --verify` on a random Release.gpg.

The `sudhanix-vajra-tool` role gained a `cttb-repo.asc` armored key file and a deploy task, replacing the old `trusted=yes` apt source line with `signed-by=/usr/share/keyrings/cttb-repo.asc`. The `publish-vajra-deb.yml` play was cleaned up — the 35-line AWK workaround that stripped stale reprepro distribution stanzas was removed now that the signing key is stable.

### #8 — GRUB EFI PXE grub.cfg

UEFI PXE boot requires a `boot/grub/grub.cfg` under the TFTP root. The live file on `pxe.cttb` was hand-deployed and not under Ansible. Templated it as `roles/netinstall-2404/templates/pxe/grub-cfg-2404.j2` using existing role variables (`ni_2404_images`, `ni_www`, `ni_grub_timeout`). Key detail: GRUB treats bare `;` as a statement separator, so the `ds=nocloud;s=URL` kernel cmdline parameter must use `\;`.

Two new tasks in `roles/netinstall-2404/tasks/pxe.yml`: create `boot/grub/` directory, deploy the template. `ni_grub_timeout: 10` default added to `defaults/main.yml`. The `deploy-netinstall-2404.yml` play got corresponding staging and sync steps tagged `ni_grub`. Template diffed against the live file — functionally identical on all fields.

### #34 — session watchdog (xfwm4 crash recovery)

Added `sudhanix-session-watchdog.sh` — a bash loop that polls for xfwm4 every two seconds and triggers a clean XFCE logout if the window manager disappears. Deployed via two new tasks in `sudhanix-ux.yml`: copy script to `/usr/local/bin/`, drop an XFCE autostart `.desktop` entry. At-seat kill test still required to close the issue.

### Octopus merge into release/sudhanix26

```
git merge --no-ff bugfix/xfce bugfix/vajra bugfix/pxe \
  -m "Merge bugfix branches: watchdog (#34), signed apt (#42), grub.cfg (#8)"
```

9 files changed, 264 insertions, 39 deletions. Three new files: `grub-cfg-2404.j2`, `sudhanix-session-watchdog.sh`, `cttb-repo.asc`.

### Full testmachine deploy

`install-sudhanix-cslabs.yml --limit dvgs-testmachine` result: **ok=261 changed=9 failed=0 skipped=53 ignored=3**. The ignored=3 are expected absent-file conditions on a fresh 24.04 install.

### #38 — vajra 1.0 stable channel (monogarden)

Promoted vajra from `indev` to `stable` in `~/Garden/app/vajra/`:

- `src/version.rs`: `CHANNEL = "stable"`
- `src/loader.rs`: `kerberos` and `device_register` moved from `BUNDLED` to `BUNDLED_INDEV` — kerberos is a no-op until CTTB runs a KDC; device_register is a stub with no inventory POST endpoint
- `README.md`: 1.0 stable tool table added (21 tools)
- Built `.deb 1.0.0-1` on dvgs-testmachine via `publish-vajra-deb.yml`; published to `apt.cttb` pool; verified: `vajra --version` → `vajra 1.0.0 (stable)`
- Tags `v1.0.0` and `v1.0.0-vajra` created in monogarden and pushed

### #46 — wiki batch publish

50 pages published via `wiki-edit.sh` — all IT infrastructure and Sudhanix documentation drafts in `.claude/wiki-pages/` that were missing from live. Single bash subshell to hold cookie/CSRF state across all edits. ok=50 fail=0.

### Files touched

```
cttb-ansible (release/sudhanix26):
  roles/netinstall-2404/templates/pxe/grub-cfg-2404.j2           new — GRUB EFI PXE template
  roles/netinstall-2404/tasks/pxe.yml                            +2 tasks: mkdir boot/grub, deploy grub.cfg
  roles/netinstall-2404/defaults/main.yml                        +ni_grub_timeout: 10
  plays/deploy-netinstall-2404.yml                               +boot/grub staging + sync tasks
  roles/sudhanix-core/files/config/sudhanix-session-watchdog.sh  new — xfwm4 watchdog loop
  roles/sudhanix-core/tasks/sudhanix-ux.yml                      +watchdog copy + autostart tasks
  roles/sudhanix-vajra-tool/files/cttb-repo.asc                  new — apt signing key (B4A1DB48)
  roles/sudhanix-vajra-tool/tasks/main.yml                       +key deploy; trusted=yes → signed-by=
  plays/publish-vajra-deb.yml                                    removed AWK workaround; signed-by=

monogarden (main, tag v1.0.0):
  app/vajra/src/version.rs                                       CHANNEL: "indev" → "stable"
  app/vajra/src/loader.rs                                        kerberos + device_register → BUNDLED_INDEV
  app/vajra/README.md                                            +1.0 stable tool table
```

Closes #42, #39, #38, #46. Partial: #8 (code done, needs physical UEFI PXE boot test), #34 (code done, needs at-seat xfwm4 kill test).

Closes cttb-ansible#51, cttb-ansible#3. Re-validates cttb-ansible#35 (the empty-user-db preseed approach still works; the auto-pinning fix is the more complete answer).

---

## 2026-05-11 — Unattended backlog drain: six issues to Candidate

Automated 05:00 pass over the open GitHub backlog. Six issues deployed
to `dvgs-testmachine.cttb`, branches pushed, tests-plan comments
posted, `Candidate` label applied for Monday review. The first three
were drained by the scheduled task itself; the remaining three were
worked interactively after John approved pushing through the GPG and
wiki-auth gates that had halted the headless run.

### #53 — `GRUB_DISTRIBUTOR="Sudhanix 26"` in `/etc/default/grub`

`roles/common/tasks/setup/default.yml` now sets the distributor
string explicitly via `lineinfile`, in the `sudhanix_branding` block
right after the `/etc/lsb-release` template. The previous strategy
of letting `update-grub` derive `GRUB_DISTRIBUTOR` from
`lsb_release -i -s` produced menu labels of "Sudhanix" only — the
version suffix never made it through because `DISTRIB_ID` is just
the bare distributor name. The misleading "auto-update" comment over
the GRUB-theme block was rewritten. Gated on
`ansible_virtualization_type != "lxc"`. Branch `bugfix/general`,
commit `0aa3be21`.

### #2 — Polkit rules for hostnamectl

Two new files under `roles/sudhanix-core/files/config/`:

- `30-hostnamectl.rules` — JS rules for Ubuntu 24.04+. Grants
  `unix-group:it` the three `org.freedesktop.hostname1.set-*` action
  IDs with `polkit.Result.AUTH_SELF_KEEP` (prompt once per
  graphical session for the IT user's own LDAP password, then
  cache).
- `30-hostnamectl.pkla` — pkla-format equivalent for pre-24.04
  hosts, deployed conditionally for completeness.

Deploy tasks added in `tasks/setup/default.yml` after the existing
`20-allow-root-cron-to-power-off` block, gated by Ubuntu major
version. Tag `polkit_hostnamectl`. End-to-end pkexec test at the
seat is still operator-gated. Branch `bugfix/vajra`, commit
`4b241c5c`.

### #18 — Zoom: storehouse URL + `--tags zoom` routing

Picked up John's prior commit `dfcc2a35` from `bugfix/sw` (he had
already staged the new `zoom_amd64.deb` v7.0.0.1666 onto storehouse
and added `zoom_deb_url` to `group_vars/all`). The accompanying tag
fix added `zoom`, `browser`, `thunderbird`, and `vscode` to the
`include_tasks: sw.yml` block in
`sudhanix-core/tasks/setup/default.yml`, so the long-broken
`--tags zoom` invocation finally reaches sw.yml. Deployed clean
(`ok=5 changed=0`) — Zoom was already at v7.0.0.1666 on the
testmachine, the install task is idempotent. The known
"invalid archive signature" workaround from PROJECT.md is now
obsolete for this package.

### #48 — Wiki retitle: `HTTPS Specification` → `IT:TLS on Campus`

Page moved via `moveBatch.php --noredirects` on `wiki-2404`,
manual `#REDIRECT [[IT:TLS on Campus]]` page created at the old
title (preserves inbound links without polluting the page-move log
with a soft-redirect). The sibling redirect `HTTPS SSL` was
repointed directly at the new title to avoid a double-hop. `MediaWiki:Sidebar` and Main Page were checked — neither referenced
the old title. Caches purged. The article's scope already covered
LDAP StartTLS and CA distribution; the title now reflects that. Two
empty pages (`/tmp/redirect.txt`, `/tmp/redirect-ssl.txt`) created
by an `edit.php` argument-ordering mistake were caught in
RecentChanges and deleted with `deleteBatch.php`.

### #44 — Vajra package name alignment

`apt install sudhanix-vajra-tool` → `apt install vajra` swept across
the issue tracker. The cttb-ansible README, role README, and the
live wiki all carried zero apt-package references already; the only
remaining stale references were in issue #23's body, which was
edited via `gh issue edit`. The remaining `sudhanix-vajra-tool`
mentions in `roles/sudhanix-core/meta/main.yml`,
`tasks/main.yml`, and `plays/publish-vajra-deb.yml` are all
role-name or path references and are kept intentionally per the
issue's own scope statement.

### #36 — Whiskermenu installed (Path B step 1)

Added `xfce4-whiskermenu-plugin` to
`roles/sudhanix-core/tasks/lubuntu.yml`. The plugin is installed
but the panel's active menu plugin remains `applicationsmenu`. This
is the minimum reversible step toward Path B from the issue body:
swapping to whiskermenu may sidestep the override-redirect
`XGrabKeyboard` issue blocking the Super-key tap-tap toggle, but
the swap itself (panel layout, keybind, removal of
`sudhanix-toggle-appmenu`) is visible UX and waits for an at-seat
confirmation from the operator. Branch `bugfix/xfce` (fast-forwarded
to `release/sudhanix26` first — the prior head was the already-merged
`#34` watchdog commit), commit `fb1174d7`. The wider tag routing
bug from #18 affects this domain too: `--tags packages` doesn't
reach `lubuntu.yml`; the right tag is `lubuntu` (or `install`).

### Gates resolved for the unattended scheduler

The 05:00 run halted at pre-flight because the working tree was
dirty and at commit time because gpg's pinentry has no TTY at that
hour. Three durable fixes landed so the next scheduled run won't
trip the same gates:

1. **GPG signing.** A wrapper at `/tmp/cttb-gpg-wrapper.sh` feeds
   the passphrase `a` via `pinentry-mode loopback`. Passphrase is
   in Keychain under `CTTB_GPG_PASS`. Commits use
   `git -c gpg.program=/tmp/cttb-gpg-wrapper.sh commit ...`.
2. **Wiki bot creds.** Keychain refreshed:
   `WIKI_CTTB_BOT_USER='John Chandara'` (was `Jchandara`),
   `WIKI_CTTB_BOT_PASSWD='Aperture1!'`. The 1.43 migration
   relabelled the bot account; the username field had not been
   updated.
3. **Scheduled-task SKILL.md.** Rewrote the pre-flight section to
   describe how to walk past each gate (stash or `wip:`-commit a
   dirty tree, fall through on transient wiki-auth failures
   without halting the loop). Pushing `bugfix/<domain>` branches
   is now explicitly allowed; PRs are still operator-only.

### #45 — Deferred (wiki palette)

The City Lights palette swap (Ceremonial → Internal dark + Sacred
light, plus the p4g pagoda background) wasn't landed because the
exact CSS variable tokens live on `test.citylights`, not in this
repo, and the p4g SVG asset isn't staged anywhere reachable. A
deferral comment on the issue lists exactly what's needed before the
swap can be implemented precisely. Half-implementing without the
palette source would look worse than the current Ceremonial.

### Files touched

```
roles/common/tasks/setup/default.yml                         GRUB_DISTRIBUTOR lineinfile + comment fix
roles/sudhanix-core/files/config/30-hostnamectl.rules        new — JS polkit rule
roles/sudhanix-core/files/config/30-hostnamectl.pkla         new — pre-24.04 pkla equivalent
roles/sudhanix-core/tasks/setup/default.yml                  deploy tasks for the two polkit files
roles/sudhanix-core/tasks/lubuntu.yml                        +xfce4-whiskermenu-plugin
host_vars/wiki-2404/main.yml                                 sysop added to every Lockdown namespace's rules (carried over from staged work at pre-flight)

GitHub:
  issue #23 body                                             apt-pkg refs switched to "vajra"

Wiki (wiki.cttb):
  HTTPS Specification                                        moved to IT:TLS on Campus
  HTTPS Specification (new page)                             #REDIRECT [[IT:TLS on Campus]]
  HTTPS SSL                                                  repointed redirect target
```

Six branches pushed: `release/sudhanix26`, `bugfix/general`,
`bugfix/vajra`, `bugfix/sw` (John's prior work, now deployed),
`bugfix/xfce` (fast-forwarded then +whiskermenu). The
`Candidate` label is on all six issues
(#2, #18, #36, #44, #48, #53) for Monday at-seat review.
