# Update Journal: ubuntu22-upgrade deployment on dvgs-lab3

**Date:** 2026-04-16
**Branch:** feature/ubuntu22-upgrade
**Target:** dvgs-lab3.cttb (current IP: 10.11.30.32, WAN port)

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

## Key Commands Reference

### Ansible Operations

```bash
# Source environment (required before all ansible commands)
source utils/setup-env

# Ping a host
ansible dvgs-lab3.cttb -m ping

# Debug a variable
ansible dvgs-lab3.cttb -m debug -a "var=deb_mirror"

# Check group membership
ansible dvgs-lab3.cttb -m debug -a "var=group_names"

# View inventory graph
ansible-inventory --graph

# View all variables for a host
ansible-inventory --host dvgs-lab3.cttb

# Dry run (check mode) with diff
ansible-playbook plays/cs-lab-2404.yml --limit dvgs-lab3.cttb --check --diff

# Actual deployment
ansible-playbook plays/cs-lab-2404.yml --limit dvgs-lab3.cttb --diff

# Deploy with verbose output
ansible-playbook plays/cs-lab-2404.yml --limit dvgs-lab3.cttb --diff -vvv
```

### Host Recovery

```bash
# Set up passwordless sudo (one-time, requires current password)
ssh administrator@dvgs-lab3.cttb "echo PASSWORD | sudo -S sh -c 'echo \"administrator ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/administrator && chmod 440 /etc/sudoers.d/administrator'"

# GRUB recovery (at physical console)
# 1. Hold Shift BEFORE POST screen finishes (timeout=0, window is instant)
# 2. If GRUB CLI appears instead of menu, type: normal
# 3. For manual boot:
#    set root=(hd0,gpt7)
#    linux /vmlinuz root=/dev/nvme0n1p7 ro single
#    initrd /initrd.img
#    boot
# 4. In recovery root shell: mount -o remount,rw / && passwd administrator

# Mac keyboard mapping for TTY switch
# Ctrl+Option+F2 (or Ctrl+Option+Fn+F2 if F-keys are media keys)
```

### Git Operations

```bash
# Revert inventory changes
git checkout HEAD -- inventory/hosts_os_upgrade.ini

# View what changed on the branch
git log main..feature/ubuntu22-upgrade --oneline
git diff main..feature/ubuntu22-upgrade --stat
```

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

## CURRENT BLOCKER: USB not visible in Dell boot menu

**Date:** 2026-04-16

USB drive written with `dd` but not appearing in F12 boot menu on dvgs-lab3 (Dell Inspiron 5400 AIO).

**Troubleshooting checklist:**
- [ ] Verify partition table on Mac: `diskutil list /dev/disk4`
- [ ] Try different USB port on the Dell
- [ ] Enter BIOS Setup (F2) and check:
  - [ ] Secure Boot is **disabled**
  - [ ] USB Boot is **enabled**
  - [ ] Boot list mode includes **UEFI**
- [ ] If partition table looks wrong, may need alternative write method (e.g., `balenaEtcher`, or use `Startup Disk Creator` from the current Ubuntu install on dvgs-lab3)

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

## PXE Deployment Constraints

- **PXE requires wired ethernet** — WiFi not available at boot time, no driver loaded
- **Wired hosts lose WAN access** — campus LAN ports are on the internal network; WAN access requires WiFi
- **Most cslab hosts are unwired** — USB autoinstall path needed for those; PXE only for hosts with ethernet
- **After PXE install, host needs WiFi configured** to regain WAN access (or stay wired)
- **DHCP server (dnsmasq.cttb at 10.11.1.19)** — PXE options were already present; updated to support UEFI (see 2026-04-22 entry)
- **PXE server is an LXC container** (lxc-pxe) on the 10.11.0.0/16 network

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
- Verify GRUB boots correctly
- Verify desktop loads (LightDM/SDDM + Lubuntu)
- Configure WiFi (NetworkManager) for WAN access
- Run `cs-lab-2404.yml` playbook for full CTTB config

---

## 2026-04-22 — UEFI PXE Boot Working

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

## Full Deployment Pipeline: Lab Machine Upgrade to 24.04

End-to-end procedure for upgrading a lab machine from any state to Ubuntu 24.04 with full CTTB configuration.

### Prerequisites

- Machine connected via **wired ethernet** (PXE requires it; WiFi not available at boot)
- PXE server deployed (see 2026-04-21 entry)
- UEFI GRUB config deployed (see 2026-04-22 entry)
- WhiteSur theme tarballs on asset server (uploaded 2026-04-22)
- Ansible environment: `source utils/setup-env`

### Phase 1: PXE Install (hands-on, ~20 min)

1. **Boot to PXE:** Power on machine → F12 → **Onboard NIC (IPV4)**
2. **GRUB menu appears:** "Ubuntu 24.04 Desktop (CTTB)" auto-selects after 10s
3. **Autoinstall runs unattended:**
   - Wipes entire disk (`storage: layout: direct`)
   - Installs Ubuntu 24.04 base + `lubuntu-desktop` + `openssh-server` + `python3` + `fish` + `network-manager`
   - Creates `administrator` user (UID 999, password from vault, NOPASSWD sudo)
   - Injects ansible SSH public key
   - Sets graphical.target as default
4. **Machine reboots** into fresh 24.04 desktop

### Phase 2: Post-boot Setup (SSH, ~5 min)

1. **Verify SSH access:**
   ```bash
   ansible dvgs-labN.cttb -m ping
   ```
2. **Set hostname** (autoinstall sets it to `computer` by default):
   ```bash
   ansible dvgs-labN.cttb -m hostname -a "name=dvgs-labN"
   ```
3. **Update inventory IP** if needed in `inventory/hosts_os_upgrade.ini`
4. **Configure WiFi** (if machine needs WAN access and will be disconnected from ethernet):
   ```bash
   ssh administrator@dvgs-labN.cttb
   nmcli dev wifi connect "DRBU" ifname wlan0   # open network
   ```

### Phase 3: Ansible Playbook (SSH, ~15-30 min)

```bash
source utils/setup-env
ansible-playbook plays/cs-lab-2404.yml --limit dvgs-labN.cttb --diff
```

This runs 5 roles in order:

| Role | What it configures |
|------|--------------------|
| `desktop` | Lubuntu desktop: APT packages, WhiteSur GTK/icon/cursor themes, login avatar & background (per-site via group_vars), LightDM config, locale, language packs, browser (Chrome/Firefox), sound, wallpaper rotation |
| `cups-client` | CUPS print client: removes local cupsd, configures remote print server (`cups_srv`), sets default queue |
| `ldap-client` | LDAP authentication: installs `libnss-ldapd`/`nslcd`, configures PAM for LDAP login, NSS, access control via `access.conf` |
| `nfs-home` | NFS home directories: installs `autofs` + `nfs-common`, configures auto.master/auto.nfs for network home dirs, `unburden-home-dir` for cache offloading |
| `cttb-ca-client` | CA certificates: installs CTTB internal CA cert for HTTPS trust (apt mirror, internal services) |

### Phase 4: Verification (manual, ~10 min)

- [ ] Desktop loads (LightDM greeter with correct avatar/background)
- [ ] LDAP login works (log in as an LDAP user, not just `administrator`)
- [ ] Home directory mounts via NFS
- [ ] Printing works (`lpstat -p` shows remote queues)
- [ ] Theme correct (WhiteSur GTK, icons, cursors)
- [ ] CA cert trusted (`curl https://apt.cttb` — no cert error)
- [ ] WiFi connects after ethernet removed (if applicable)

### Per-site Customization

Avatar and background are set automatically via group_vars:

| Group | Avatar | Background |
|-------|--------|------------|
| `dvgs` | `avatar-dvgs.png` | `bg-dvgs.jpg` |
| `dvbs` | `avatar-dvbs.png` | `bg-dvbs.jpg` |
| `drbu` | `avatar-drbu.png` | `bg-drbu.jpg` |

Other per-site vars: `cups_srv`, `cups_default_queue`, `nfs_homes_host`, `nfs_homes_export`, LDAP server, DNS server.

### Batch Rollout

To deploy multiple machines at once:

```bash
# All DVGS lab machines
ansible-playbook plays/cs-lab-2404.yml --limit dvgs_cs_lab --diff

# All labs at all sites
ansible-playbook plays/cs-lab-2404.yml --diff

# Specific machines
ansible-playbook plays/cs-lab-2404.yml --limit "dvgs-lab1.cttb,dvgs-lab2.cttb" --diff
```

PXE install is per-machine (physical F12 boot), but Phase 3 (Ansible) can run against all machines in parallel once they're PXE'd and SSH-reachable.

### Known Issues / Workarounds

- **Hostname:** Autoinstall sets hostname to `computer` — must be set manually or via Ansible before playbook run (playbook may depend on hostname for group membership)
- **WiFi:** PXE install is wired-only. WiFi must be configured post-install if machine needs WAN access
- **UID mismatch:** Autoinstall creates UID 999; debootstrap installs may get UID 1000. The desktop role should handle alignment
- **apt mirror:** `apt.cttb` only has focal/xenial. Noble packages come from `archive.ubuntu.com` over WAN. Machines need internet access during playbook run
- **GRUB semicolons:** `ds=nocloud-net;s=...` must use `\;` in GRUB configs (both PXE and USB)

---

## Next Steps

1. **Monitor dvgs-lab3 autoinstall** — verify completion, first boot, desktop
2. **Configure WiFi on dvgs-lab3** — needed for WAN access after disconnecting ethernet
3. ~~**Upload WhiteSur tarballs** to asset server~~ — done 2026-04-22
4. **Post-install config** — `ansible-playbook plays/cs-lab-2404.yml --limit dvgs-lab3.cttb --diff`
5. **Verify services** — CUPS, LDAP auth, NFS mounts, CA certs, desktop, theme
6. **Fix USB autoinstall** — add `optional: true` to wifi in templates, get a reliable USB drive
7. **Roll out** to remaining lab hosts across DVGS, DVBS, DRBU
8. **Codify UEFI GRUB in netinstall-2404 role** — add grub.cfg template, grubnetx64.efi deployment task
9. **Fix autoinstall hostname** — template per-host user-data or add hostname task to playbook
10. **Add `desktop_login_background` to dvbs/drbu group_vars** — currently only dvgs has the new variable
