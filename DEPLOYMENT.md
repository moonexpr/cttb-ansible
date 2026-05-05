# Deployment Guide: Lab Machine Upgrade to Ubuntu 24.04

End-to-end procedure for upgrading a CTTB lab machine from any state to Ubuntu 24.04 with full configuration.

---

## Prerequisites

- Machine connected via **wired ethernet** (PXE requires it; WiFi not available at boot)
- PXE server deployed (UEFI GRUB + autoinstall profiles)
- WhiteSur theme tarballs on asset server (`storehouse.cttb/ansible/`)
- Ansible environment: `source utils/setup-env`

---

## Phase 1: PXE Install (~20 min)

### Triggering PXE boot remotely (primary method)

Use `efibootmgr` to set a one-time network boot — no physical access needed:

```bash
# Single machine
ansible-playbook plays/pxe-reboot.yml -l dvgs-lab3.cttb

# Dry run (shows what would happen without rebooting)
ansible-playbook plays/pxe-reboot.yml -l dvgs-lab3.cttb --check

# Batch: all DVGS lab machines
ansible-playbook plays/pxe-reboot.yml -l dvgs_cs_lab

# All labs at all sites
ansible-playbook plays/pxe-reboot.yml -l dvgs_cs_lab:dvbs_cs_lab:drbu_cs_lab
```

The playbook installs `efibootmgr` if missing, finds the NIC(IPV4) boot entry automatically, sets it as one-shot next boot (`-n`), and reboots. Boot order reverts to disk after one boot.

**Requirements:** Machine must be SSH-reachable and running a UEFI OS. Works on the existing 20.04 installs.

### Fallback: manual F12 boot

If the machine is powered off or SSH is unreachable:
1. Power on → **F12** → **Onboard NIC (IPV4)**

### What happens after PXE boot

1. **GRUB menu appears:** "Ubuntu 24.04 Desktop (CTTB)" auto-selects after 10s
2. **Autoinstall runs unattended:**
   - Wipes entire disk (`storage: layout: direct`)
   - Installs Ubuntu 24.04 base + `lubuntu-desktop` + `openssh-server` + `python3` + `fish` + `network-manager`
   - Creates `administrator` user (UID 999, password from vault, NOPASSWD sudo)
   - Injects ansible SSH public key
   - Sets graphical.target as default
3. **Machine reboots** into fresh 24.04 desktop

---

## Phase 2: Post-boot Setup (SSH, ~5 min)

1. **Verify SSH access:**
   ```bash
   ansible dvgs-labN.cttb -m ping
   ```
2. **Hostname** — set automatically by common role (`ansible.builtin.hostname` task). No manual step needed.
3. **Update inventory IP** if needed in `inventory/hosts_os_upgrade.ini`
4. **Configure WiFi** (if machine needs WAN access and will be disconnected from ethernet):
   ```bash
   ssh administrator@dvgs-labN.cttb
   nmcli dev wifi connect "DRBU" ifname wlan0   # open network
   ```

---

## Phase 3: Ansible Playbook (SSH, ~15-30 min)

```bash
source utils/setup-env
ansible-playbook plays/cs-lab-2404.yml --limit dvgs-labN.cttb --diff
```

This runs 6 roles in order:

| Role | What it configures |
|------|--------------------|
| `common` | Hostname, SSH keys, needrestart, apt sources, sysctl, packages, NM, sudoers |
| `time-server` | systemd-timesyncd on 24.04+ (legacy ntp for older Ubuntu) |
| `desktop` | Lubuntu desktop: APT packages, WhiteSur GTK/icon/cursor themes, login avatar & background (per-site via group_vars), LightDM config, locale, language packs, browser (Chrome/Firefox), sound, wallpaper rotation, XFCE panel, xfwm4, terminal, Thunderbird |
| `cups-client` | CUPS print client: removes local cupsd, configures remote print server (`cups_srv`), sets default queue |
| `ldap-client` | LDAP authentication: installs `libnss-ldapd`/`nslcd`, configures PAM for LDAP login, NSS, access control via `access.conf` |
| `nfs-home` | NFS home directories: installs `autofs` + `nfs-common`, configures auto.master/auto.nfs for network home dirs, `unburden-home-dir` for cache offloading |
| `cttb-ca-client` | CA certificates: installs CTTB internal CA cert for HTTPS trust (apt mirror, internal services) |

---

## Phase 4: Verification (manual, ~10 min)

- [ ] Desktop loads (LightDM greeter with correct avatar/background)
- [ ] LDAP login works (log in as an LDAP user, not just `administrator`)
- [ ] Home directory mounts via NFS
- [ ] Printing works (`lpstat -p` shows remote queues)
- [ ] Theme correct (WhiteSur GTK, icons, cursors)
- [ ] CA cert trusted (`curl https://apt.cttb` — no cert error)
- [ ] WiFi connects after ethernet removed (if applicable)

---

## Per-site Customization

Avatar and background are set automatically via group_vars:

| Group | Avatar | Background |
|-------|--------|------------|
| `dvgs` | `avatar-dvgs.png` | `bg-dvgs.jpg` |
| `dvbs` | `avatar-dvbs.png` | `bg-dvbs.jpg` |
| `drbu` | `avatar-drbu.png` | `bg-drbu.jpg` |

Other per-site vars: `cups_srv`, `cups_default_queue`, `nfs_homes_host`, `nfs_homes_export`, LDAP server, DNS server.

---

## Batch Rollout

```bash
# All DVGS lab machines
ansible-playbook plays/cs-lab-2404.yml --limit dvgs_cs_lab --diff

# All labs at all sites
ansible-playbook plays/cs-lab-2404.yml --diff

# Specific machines
ansible-playbook plays/cs-lab-2404.yml --limit "dvgs-lab1.cttb,dvgs-lab2.cttb" --diff
```

PXE install is per-machine (F12 or `pxe-reboot.yml`), but Phase 3 (Ansible) can run against all machines in parallel once they're PXE'd and SSH-reachable.

---

## PXE Deployment Constraints

- **PXE requires wired ethernet** — WiFi not available at boot time, no driver loaded
- **Wired hosts lose WAN access** — campus LAN ports are on the internal network; WAN access requires WiFi
- **Most cslab hosts are unwired** — USB autoinstall path needed for those; PXE only for hosts with ethernet
- **After PXE install, host needs WiFi configured** to regain WAN access (or stay wired)
- **DHCP server (dnsmasq.cttb at 10.11.1.19)** — PXE options present; supports UEFI via `dhcp-match`
- **PXE server is an LXC container** (lxc-pxe) on the 10.11.0.0/16 network

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

### Remote Screenshot (no VNC needed)

```bash
# Screenshot the LightDM greeter (runs as root on :0)
ssh administrator@HOST 'sudo DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 scrot /tmp/screenshot.png'
scp administrator@HOST:/tmp/screenshot.png .

# Screenshot a logged-in user session
ssh administrator@HOST 'sudo DISPLAY=:0 XAUTHORITY=/home/USER/.Xauthority scrot /tmp/screenshot.png'
```

Requires `scrot` (installed via lubuntu.yml). Works over SSH + ProxyJump.

### Git Operations

```bash
# Revert inventory changes
git checkout HEAD -- inventory/hosts_os_upgrade.ini

# View what changed on the branch
git log main..feature/ubuntu22-upgrade --oneline
git diff main..feature/ubuntu22-upgrade --stat
```

---

## Known Issues / Workarounds

- **Hostname:** Autoinstall sets hostname to `computer` — corrected automatically by common role
- **WiFi:** PXE install is wired-only. WiFi must be configured post-install if machine needs WAN access
- **UID mismatch:** Autoinstall creates UID 999; debootstrap installs may get UID 1000. The desktop role should handle alignment
- **apt mirror:** `apt.cttb` noble sync started 2026-04-30. Until verified, use `deb_mirror=http://archive.ubuntu.com` override
- **GRUB semicolons:** `ds=nocloud-net;s=...` must use `\;` in GRUB configs (both PXE and USB) or double-quote escaping `ds="nocloud-net;s=..."`
- **needrestart:** Ubuntu 24.04 installs needrestart by default, which hangs apt in non-interactive sessions. The common role deploys auto-restart config before any apt operations
- **Firefox:** snap package is blocked on campus. Currently skipped. Options: Mozilla tarball (like Thunderbird), or wait for PPA access
- **Chrome:** Uses apt.cttb mirror (HTTP). `dl.google.com` blocked by campus firewall for HTTPS key fetch
