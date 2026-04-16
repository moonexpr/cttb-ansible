# Update Journal: ubuntu22-upgrade deployment on dvgs-lab3

**Date:** 2026-04-16
**Branch:** feature/ubuntu22-upgrade
**Target:** dvgs-lab3.cttb (10.11.13.78)

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

### 5. APT mirror unreachable (CURRENT BLOCKER)

**Problem:** `apt.cttb` (internal APT mirror) refuses connections from dvgs-lab3. The `common-20.04` role fails trying to download the CTTB repo GPG key from `http://apt.cttb/cttb-repos/cttb-repo.gpg.key`.

**Status:** Under investigation. This is a network/service issue, not a playbook bug.

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

## Deployment Log

**Status:** Dry run partially passed. Blocked on APT mirror connectivity (`apt.cttb` unreachable from dvgs-lab3).
