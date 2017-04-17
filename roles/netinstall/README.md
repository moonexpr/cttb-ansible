# Overview

This role sets up pxe and tftp to allow for network installs

# ISOS
If you look at default values, the two isos used as the base for all installations are being fetched from theoverseer, put them there inside ansible_assets/isos. This shuold probably change in the future, maybe move to the fileserver/storage server.

# Booting files
Stuff like lpxelinux.0 and memtest/memdisk can be found in the following packages:
- pxelinux
- syslinux
- syslinux-common
- memtest86+ (this gives a diff bin than memtest86 I downloaded tho)
