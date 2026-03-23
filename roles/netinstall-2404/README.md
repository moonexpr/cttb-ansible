# netinstall-2404

Sets up PXE network boot with Ubuntu 24.04 LTS autoinstall for headless OS deployment.

## Overview

Ubuntu 24.04 dropped the traditional debian-installer (preseed). This role uses the
new **autoinstall** system (subiquity + cloud-init) to provide fully unattended
network installations over PXE.

## How it works

1. The live-server ISO is fetched and extracted to serve the kernel/initrd over TFTP
2. Autoinstall user-data/meta-data files are generated and served over HTTP
3. PXE boot menu entries pass `autoinstall ds=nocloud-net` to the kernel
4. The installer runs headless — no user interaction required
5. After install, SSH + Ansible key are in place for immediate configuration

## Autoinstall profiles

- **desktop** — Full Lubuntu desktop (headless install, graphical after reboot)
- **desktop-minimal** — Lubuntu core only (lean base for Ansible to build on)
- **server** — Server packages only, no GUI

## Prerequisites

- Place the Ubuntu 24.04.2 live-server ISO at `{{ansible_assets_url}}/isos/`
- DHCP must point PXE clients to the TFTP server (existing dhcpd role)
- Local apt mirror at `apt.cttb` should mirror the `noble` suite

## Usage

```yaml
- hosts: pxe-server
  roles:
    - netinstall-2404
```

Then PXE-boot any Computer Lab machine and select the desired profile from the menu.

## Differences from the legacy netinstall role

| Feature         | netinstall (Xenial)    | netinstall-2404 (Noble)       |
|----------------|------------------------|-------------------------------|
| Installer      | debian-installer       | subiquity (autoinstall)       |
| Config format  | preseed (.seed)        | cloud-init YAML (user-data)   |
| ISO type       | mini.iso               | live-server ISO               |
| Architectures  | amd64, i386            | amd64 only                    |
| EFI support    | No                     | Planned (TODO)                |
