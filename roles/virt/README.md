# Overview
Installs virtualbox, lxc or kvm based on specified variables. By default it
doesn't do anything

# LXC
## Adding a LXC controller
To add a host as a lxc controller (ie running containers), this host should end
up in the lxd-host group in the _hosts_ file.

#QEMU
Please note at that this time *all filesystems need to be pre-created* as the
role does not do that. Provisions have been made so that will be possible, but
code isn't there right now.
