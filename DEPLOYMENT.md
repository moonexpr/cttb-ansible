# Deployment Guide: Lab Machine Upgrade to Ubuntu 24.04

End-to-end procedure for upgrading a CTTB lab machine from any state to Ubuntu 24.04 with full configuration.

---

## Prerequisites

- Machine connected via **wired ethernet** (PXE requires it; WiFi not available at boot)
- PXE server deployed (UEFI GRUB + autoinstall profiles)
- WhiteSur theme tarballs on asset server (`storehouse.cttb/ansible/`)
- Ansible environment: `source utils/setup-env`

---

## The one-command path

`sudhanix26-rollout` is the canonical way to deploy a host. One invocation reimages the machine and returns it configured:

```bash
source utils/setup-env
ansible-playbook -i inventory/sudhanix26_hosts.ini plays/sudhanix26-rollout.yml \
    -l <hostname>.cttb --skip-tags zoom --diff \
    --vault-password-file <vault-pw-file> --ask-become-pass
```

The playbook triggers the PXE reimage, waits for the host to drop off the network, autoinstall, and return on the fresh image, then applies the Ansible roles. The deployment is a destructive fresh install, not an in-place upgrade. The disk is wiped and the host is rebuilt from a clean Ubuntu 24.04 base, so a host's Sudhanix state is described entirely by that base plus the roles plus its site variables, with no per-host drift to carry forward. Run from a checkout at the `sudhanix26.0.0` tag or later, since that tag is the validated baseline.

`--skip-tags zoom` is standard on every run. The Zoom client ships as a pre-installed `.deb` whose archive signature is invalid, so the Zoom upgrade task is skipped while the rest of the software batch installs. The become password is required, since the autoinstalled `administrator` account is an ordinary sudoer, not a passwordless one.

The phases below document what each stage does and the staged path used for a lab-wide rollout. `sudhanix26-rollout-stage1` is the PXE reimage trigger and `sudhanix26-rollout-stage2` is the Ansible configuration; the orchestrator runs both with the wait between them built in.

---

## Phase 1: PXE Install (~20 min)

### Triggering PXE boot remotely (primary method)

Use `efibootmgr` to set a one-time network boot, no physical access needed:

```bash
# Single machine
ansible-playbook plays/sudhanix26-rollout-stage1.yml -l dvgs-lab3.cttb

# Dry run (shows what would happen without rebooting)
ansible-playbook plays/sudhanix26-rollout-stage1.yml -l dvgs-lab3.cttb --check

# Batch: all DVGS lab machines
ansible-playbook plays/sudhanix26-rollout-stage1.yml -l dvgs_cs_lab

# All labs at all sites
ansible-playbook plays/sudhanix26-rollout-stage1.yml -l dvgs_cs_lab:dvbs_cs_lab:drbu_cs_lab
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
   - Creates the `administrator` user with UID 999, the vault password, and ordinary sudo rights, not passwordless sudo. Ansible runs supply the become password
   - Injects ansible SSH public key
   - Sets graphical.target as default
3. **Machine reboots** into fresh 24.04 desktop

---

## Phase 2: Post-boot Setup (SSH, ~5 min)

1. **Verify SSH access:**
   ```bash
   ansible dvgs-labN.cttb -m ping
   ```
2. **Hostname**, set automatically by the common role via the `ansible.builtin.hostname` task. No manual step needed.
3. **Update inventory IP** if needed in `inventory/sudhanix26_hosts.ini`
4. **Configure WiFi** (if machine needs WAN access and will be disconnected from ethernet):
   ```bash
   ssh administrator@dvgs-labN.cttb
   nmcli dev wifi connect "DRBU" ifname wlan0   # open network
   ```

---

## Phase 3: Ansible Playbook (SSH, ~15-30 min)

```bash
source utils/setup-env
ansible-playbook plays/sudhanix26-rollout-stage2.yml --limit dvgs-labN.cttb \
    --skip-tags zoom --diff --vault-password-file <vault-pw-file> --ask-become-pass
```

`--skip-tags zoom` is standard, since the pre-installed Zoom `.deb` has an invalid archive signature and its upgrade task fails otherwise. The become password is required for the same reason it is on the orchestrator, the autoinstalled `administrator` is an ordinary sudoer.

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
- [ ] CA cert trusted, `curl https://apt.cttb` returns no cert error
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

A lab-wide rollout does not loop `sudhanix26-rollout`. Looping the orchestrator would serialise the roughly 35-minute provision-and-wait once per host and drag a 25-host lab toward a full day. The lab pattern pipelines the wait by driving the two stages directly: reimage a batch of three with stage 1, wait about 20 minutes, configure those three with stage 2, and reimage the next three while stage 2 runs on the first.

```bash
# Reimage a batch
ansible-playbook plays/sudhanix26-rollout-stage1.yml --limit 'dvgs-lab1.cttb,dvgs-lab2.cttb,dvgs-lab3.cttb'

# Configure that batch once it has provisioned
ansible-playbook plays/sudhanix26-rollout-stage2.yml --limit 'dvgs-lab1.cttb,dvgs-lab2.cttb,dvgs-lab3.cttb' \
    --skip-tags zoom --diff --vault-password-file <vault-pw-file> --ask-become-pass

# Whole lab at once, only once every host has been PXE'd and is SSH-reachable
ansible-playbook plays/sudhanix26-rollout-stage2.yml --limit dvgs_cs_lab \
    --skip-tags zoom --diff --vault-password-file <vault-pw-file> --ask-become-pass
```

Stage 1 is per-machine, since it triggers a one-time PXE boot on each host, whether by the playbook or a manual F12. Stage 2 runs against every provisioned host in parallel, so the wait is paid once per batch rather than once per host.

---

## PXE Deployment Constraints

- **PXE requires wired ethernet**, WiFi is not available at boot time and no driver is loaded
- **Wired hosts lose WAN access**, campus LAN ports are on the internal network and WAN access requires WiFi
- **Most cslab hosts are unwired**, they need the USB autoinstall path, and PXE serves only the hosts with ethernet
- **After PXE install, host needs WiFi configured** to regain WAN access (or stay wired)
- **DHCP server (dnsmasq.cttb at 10.11.1.19)**, PXE options present, UEFI supported via `dhcp-match`
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
ansible-playbook plays/sudhanix26-rollout-stage2.yml --limit dvgs-lab3.cttb --check --diff

# Actual deployment
ansible-playbook plays/sudhanix26-rollout-stage2.yml --limit dvgs-lab3.cttb --diff

# Deploy with verbose output
ansible-playbook plays/sudhanix26-rollout-stage2.yml --limit dvgs-lab3.cttb --diff -vvv
```

### Host Recovery

```bash
# Optional operator convenience, NOT required for deployment. Sudhanix
# rollout runs pass the become password (--ask-become-pass), so the
# autoinstalled ordinary-sudoer administrator works as-is. This snippet
# only grants passwordless sudo for hand-run recovery work.
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
git checkout HEAD -- inventory/sudhanix26_hosts.ini

# View what changed on the branch
git log main..release/sudhanix26 --oneline
git diff main..release/sudhanix26 --stat
```

---

## Known Issues / Workarounds

- **Hostname:** autoinstall sets the hostname to `computer`, corrected automatically by the common role
- **WiFi:** PXE install is wired-only. WiFi must be configured post-install if machine needs WAN access
- **UID mismatch:** Autoinstall creates UID 999; debootstrap installs may get UID 1000. The desktop role should handle alignment
- **apt mirror:** `apt.cttb` is the production noble mirror. Lab hosts cannot reach `archive.ubuntu.com` directly because the campus firewall blocks it, so the earlier `deb_mirror` override is obsolete and must not be used on the fleet
- **GRUB semicolons:** `ds=nocloud-net;s=...` must use `\;` in GRUB configs (both PXE and USB) or double-quote escaping `ds="nocloud-net;s=..."`
- **needrestart:** Ubuntu 24.04 installs needrestart by default, which hangs apt in non-interactive sessions. The common role deploys auto-restart config before any apt operations
- **Firefox:** the noble `firefox` apt package is a snap-transitional stub, and snap is blocked on campus. Resolved by installing the official Mozilla tarball from `storehouse.cttb/ansible/`, the same pattern as Thunderbird, with a negative APT pin that keeps the snap stub from returning
- **Chrome:** Uses apt.cttb mirror (HTTP). `dl.google.com` blocked by campus firewall for HTTPS key fetch
