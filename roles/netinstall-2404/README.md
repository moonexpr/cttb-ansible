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
- hosts: cttb_pxe
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
| EFI support    | No                     | Yes (shim -> GRUB netboot)    |

## UEFI network boot

Both firmware generations are served from the same TFTP root, steered by DHCP
option 93 in `roles/dnsmasq`:

| Client reports          | Gets           | Then reads                        |
|-------------------------|----------------|-----------------------------------|
| arch 0 (legacy BIOS)    | `pxelinux.0`   | `pxelinux.cfg/default`            |
| arch 7 / 9 (EFI x86-64) | `grubx64.efi`  | `grub/grub.cfg`                   |

**UEFI clients go straight to GRUB — there is deliberately no shim hop.** shim
15.8 (the only version in any Ubuntu archive as of 2026-08) mis-derives its
second-stage path over netboot on the DVGS Dell Inspiron fleet, splicing the
firmware's boot-option label into the TFTP filename and dying on the fetch
(rhboot/shim#696). The consequence: **Secure Boot must be off on a client for
the netboot/install itself.** The bug is netboot-only — the installed system
boots through its on-disk shim normally, so Secure Boot goes back on after the
install. `shimx64.efi` stays staged in `files/efiboot/` for the day a fixed
signed shim ships; do not point dnsmasq back at it before verifying on a Dell.

**The GRUB prefix is load-bearing.** `grubx64.efi` is built with prefix `/grub`,
so it reads `{{ni_tftp_dir}}/grub/grub.cfg` — **not** `boot/grub/grub.cfg`. Writing
the latter is a silent no-op: the menu appears to deploy, GRUB never sees it, and
nothing errors. This cost months of confusing "my grub.cfg edits do nothing"
before `e7bbe3a0` found it. If you ever rebuild the binary with `grub-mknetdir`
or swap in a different signed build, verify the prefix still matches this path.

`grubx64.efi` must be `grubnetx64.efi.signed` (the **netboot** build, carrying the
`efinet`/`tftp` modules), not the similarly named disk-boot `grubx64.efi.signed`
from the same `grub-efi-amd64-signed` package. Both binaries ship in
`files/efiboot/`; check with `grep -a -c efinet <file>` (netboot build is non-zero).

Why the direct-to-GRUB path costs Secure Boot: `grubx64.efi` carries Canonical's
signature, not Microsoft's, and firmware only trusts Microsoft's out of the box.
The shim chain is the textbook fix for that, and it is exactly the part that is
broken on this fleet — hence the trade documented above.
