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

## Next Steps

1. **Fix USB boot** — resolve the boot menu visibility issue
2. **Upload WhiteSur tarballs** to asset server (see above)
3. **Autoinstall runs** — fully autonomous (~15-20 min)
4. **Post-install config** — `ansible-playbook plays/cs-lab-2404.yml --limit dvgs-lab3.cttb --diff`
5. **Verify services** — CUPS, LDAP auth, NFS mounts, CA certs, desktop, theme
6. **Get PXE server access** — add `pxe-server` to inventory, run `plays/netinstall-2404.yml`
7. **Roll out** to remaining dvgs_cs_lab hosts
