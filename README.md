# CTTB Ansible

Configuration management for the CTTB campus network: computer labs, servers, and network services across three institutions -- DVGS (Girls School), DVBS (Boys School), and DRBU (Dharm Realm Buddhist University).

Built on [Ansible](https://docs.ansible.com/ansible/latest/index.html). Inspired by [ansible-best-practises](https://github.com/enginyoyen/ansible-best-practises) and the [Ansible best practices guide](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html).

## Quick Start

**Prerequisites:** Ansible installed on the control machine, SSH key-based access to target hosts as the `administrator` user, and network connectivity to the `.cttb` domain.

**Always run commands from the repository root.**

```bash
# Run a playbook (preferred method)
utils/pb dvgs-cs-lab

# Apply one or more roles to a host or group
utils/ar drbu-sw-cslab desktop,cups-client,ldap-client,nfs-home

# Or use ansible-playbook directly
ansible-playbook plays/dvgs-cs-lab.yml --diff
```

The `utils/pb` wrapper sources the environment (`utils/setup-env`), sets up paths, and runs the playbook with `--diff` enabled by default. You can pass any additional `ansible-playbook` flags after the playbook name.

## Repository Structure

```
cttb-ansible/
├── plays/           Playbooks -- the entry points for all operations
├── roles/           Reusable roles implementing infrastructure components
├── inventory/       Host inventory files (INI format)
├── group_vars/      Variables applied per host group
├── host_vars/       Variables for individual hosts
├── vars/            Shared variables and encrypted vault files
├── utils/           Helper scripts (pb, ar, setup-env, etc.)
├── scripts/         Standalone shell scripts (ping sweeps, WoL, etc.)
├── library/         Custom Ansible modules (NTC plugins)
├── logs/            Playbook execution logs (not tracked in git)
└── ansible.cfg      Ansible configuration
```

## Inventory

The default inventory is set in `ansible.cfg` (`inventory/hosts_os_upgrade.ini`). Hosts are organized by institution and location:

| Group               | Description                        |
|---------------------|------------------------------------|
| `drbu_cslab`        | DRBU computer science lab          |
| `drbu_cdorm`        | DRBU girls' dormitory lab          |
| `dvgs_cslab`        | DVGS computer science lab          |
| `dvgs_dormitory`    | DVGS dormitory computers           |
| `dvbs_cslab`        | DVBS computer science lab          |
| `dvbs_community_center` | DVBS community center PCs      |
| `dvbs_library`      | DVBS library                       |

Parent groups aggregate these: `drbu_hosts`, `dvgs_hosts`, `dvbs_hosts`, and `cttb_hosts` (all).

Each host entry in the inventory defines `mac_addr` (for Wake-on-LAN) and `ansible_address`. Host-specific variables live in `host_vars/` and group-level overrides in `group_vars/`.

### Global Variables (group_vars/all)

| Variable           | Purpose                                    |
|--------------------|--------------------------------------------|
| `dns_domain`       | Internal domain (`cttb`)                   |
| `dns_srv`          | DNS server address                         |
| `apt_url`          | Local APT mirror URL                       |
| `ni_server`        | PXE/network install server URL             |
| `ansible_assets_url` | Large file hosting (ISOs, fonts, packages)|
| `ntp_servers`      | NTP server list                            |

## Playbooks

All playbooks live in `plays/`. Key categories:

### Deployment

| Playbook               | Purpose                                               |
|------------------------|-------------------------------------------------------|
| `dvgs-cs-lab`          | Full DVGS lab: desktop, printing, LDAP, NFS, CA       |
| `dvbs-3rd-9th`         | DVBS upper grades lab                                 |
| `drbu-sw-cslab`        | DRBU CS lab switch configuration                      |
| `cs-lab-2404`          | Apply Ubuntu 24.04 settings to all CS labs            |
| `netinstall-2404`      | Deploy Ubuntu 24.04 PXE/autoinstall infrastructure    |

### Infrastructure

| Playbook      | Purpose                                              |
|---------------|------------------------------------------------------|
| `gw`          | Gateway: firewall, squid proxy, content filtering    |
| `nas`         | NAS: ZFS storage, UPS, virtualization                |
| `vm`          | VM host: KVM/Qemu, ZFS, UPS                         |
| `unbound`     | DNS nameserver for .cttb zone                        |
| `asterix`     | Asterisk VoIP PBX                                    |
| `debmirror`   | APT package mirror                                   |

### Maintenance

| Playbook              | Purpose                              |
|-----------------------|--------------------------------------|
| `apt-update-autoremove` | System update + cleanup            |
| `dist-upgrade`        | Full distribution upgrade            |
| `reboot` / `shutdown` | Power management                     |
| `cron-shutdown`       | Scheduled shutdown via cron          |

### Utilities

| Playbook               | Purpose                                      |
|------------------------|----------------------------------------------|
| `util-wakeonlan`       | Send Wake-on-LAN packets to all hosts        |
| `util-ssh-copy-id`     | Distribute SSH public keys                   |
| `util-hardware-survey` | Collect hardware + OS info to CSV            |
| `util-screenshot`      | Remote screenshot via scrot for debugging    |

## Roles

Roles without a prefix are homegrown. The original convention of a `cttb.` prefix for internal roles is noted but not consistently applied.

### Core

| Role             | Description                                          |
|------------------|------------------------------------------------------|
| `common`         | Base Ubuntu setup, APT sources                       |
| `common-20.04`   | Ubuntu 20.04 variant                                 |
| `server`         | Server networking, GRUB, static interfaces           |
| `desktop`        | Desktop workstation (themes, browsers, office, etc.) |
| `desktop-20.04`  | Ubuntu 20.04 desktop variant                         |

### Network Boot

| Role              | Description                                          |
|-------------------|------------------------------------------------------|
| `netinstall`      | PXE + preseed for Ubuntu 16.04 (legacy)              |
| `netinstall-2404` | PXE + autoinstall (subiquity) for Ubuntu 24.04 LTS   |

### Network Services

| Role         | Description                                    |
|--------------|------------------------------------------------|
| `unbound`    | Recursive + authoritative DNS with DNSSEC      |
| `dhcpd`      | ISC DHCP server                                |
| `time-server`| NTP daemon                                     |

### Authentication & Security

| Role            | Description                                 |
|-----------------|---------------------------------------------|
| `ldap-client`   | LDAP client for system authentication       |
| `ldap-server`   | OpenLDAP server deployment                  |
| `cttb-ca-client` | Install CTTB Root CA certificate           |

### File & Print Services

| Role          | Description                                    |
|---------------|------------------------------------------------|
| `nfs-home`    | NFS home directory mounts with automount       |
| `cups-client` | CUPS client for network printing               |
| `cups-server` | CUPS print server                              |
| `debmirror`   | APT mirror sync and serving                    |

### Internet & Filtering

| Role        | Description                                       |
|-------------|---------------------------------------------------|
| `firehol`   | Firewall (iptables), time-based internet limits    |
| `squid`     | HTTP/HTTPS proxy                                   |
| `e2guardian` | Content filtering proxy with HTTPS MITM           |

### Storage & Virtualization

| Role   | Description                                      |
|--------|--------------------------------------------------|
| `virt`  | KVM/Qemu/VirtualBox/LXC host setup              |
| `zfs`   | ZFS filesystem and pools                         |
| `ups`   | Network UPS Tools (NUT)                          |

### Other Services

| Role          | Description                             |
|---------------|-----------------------------------------|
| `asterisk`    | VoIP PBX with phone provisioning        |
| `koha`        | Integrated Library System               |
| `git`         | Gitolite3 + Gitweb hosting              |
| `logcentral`  | Centralized syslog with rotation        |
| `hp-procurve` | HP ProCurve switch management           |

## Variable Precedence

From lowest to highest priority:

1. Role defaults (`roles/<role>/defaults/main.yml`)
2. Global variables (`group_vars/all`)
3. Group variables (`group_vars/<group>`)
4. Host variables (`host_vars/<hostname>`)
5. Playbook vars / extra vars (`-e`)
6. Vault secrets (`vars/jc_passwds.enc.yml`)

See the [Ansible variable precedence docs](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#understanding-variable-precedence) for the full list.

## Common Workflows

### Deploying a New Lab Machine

1. Define the host in the inventory with `mac_addr` and `ansible_address`.
2. Add it to the appropriate group.
3. Wake it up and copy the SSH key:
   ```bash
   utils/pb util-wakeonlan --limit <hostname>
   # Then copy SSH key (password auth needed for first run)
   ansible <hostname> -m raw -a 'mkdir -p ~/.ssh && ...' -e 'ansible_ssh_pass=<password>'
   ```
4. Run the lab playbook:
   ```bash
   utils/pb dvgs-cs-lab --limit <hostname>
   ```

### Running a Hardware Survey

```bash
utils/pb util-hardware-survey
```

Outputs `~/hardware_survey.csv` with CPU, RAM, storage, OS, motherboard, USB, and GPU info for every reachable host.

### System Updates

```bash
# Update and clean all hosts
utils/pb apt-update-autoremove

# Full dist-upgrade on a specific group
utils/pb dist-upgrade --limit dvgs_cslab
```

### PXE Network Installation (Ubuntu 24.04)

The `netinstall-2404` role sets up the PXE server for automated Ubuntu 24.04 installs using subiquity/autoinstall (cloud-init YAML), replacing the legacy preseed approach from `netinstall`.

```bash
utils/pb netinstall-2404
```

## Assets

Large files (ISOs, `.deb` packages, fonts) are hosted on the PXE web server at `ansible_assets_url` and fetched during playbook runs. They are not stored in git. This directory should be backed up as part of the web server backup.

## Encrypted Secrets

Passwords and sensitive data are stored in `vars/jc_passwds.enc.yml`, encrypted with [Ansible Vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html).

```bash
# Edit the vault file
ansible-vault edit vars/jc_passwds.enc.yml

# Run a playbook that needs vault secrets
utils/pb gw --ask-vault-pass
```

## Notes

- Hosts are migrating from **Ubuntu 20.04 LTS** to **24.04 LTS** (noble). Test machine (`dvgs-testmachine`) is on 24.04.
- Desktop environment: **XFCE4** with WhiteSur-Dark theme, Plank dock, macOS-style greeter.
- The `administrator` user is the default `remote_user` for all SSH connections.
- Host key checking is disabled in `ansible.cfg` for ease of reprovisioning.
- SSH agent forwarding and pipelining are enabled for performance.
- Execution logs are written to `logs/runtime.log`.
- Campus firewall blocks snap store, ppa.launchpad.net, and most external HTTPS repos. Software must be mirrored locally (`apt.cttb`, `storehouse.cttb`).
