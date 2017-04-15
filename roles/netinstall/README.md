# Overview

This role sets up pxe and tftp to allow for network installs

# Requirements
For this to work you need to provide the kernel and initrd images at the
ansible_assets_url/netinstall . This are named after the name of the image and
arch , ie xenial-amd64-linux and xenial-amd64-initrd.gz

# Manual STEPS
For the time being populating the "ubuntu" family directory with menus and
kernels etc is still to be done manually. Equally creating the relevant dirs in
/srv/isos/ for the nfsroot is still manual
