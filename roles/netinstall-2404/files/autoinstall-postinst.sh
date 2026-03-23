#!/bin/bash
#
# Post-installation script for Ubuntu 24.04 autoinstall deployments.
# Called via late-commands or run manually after first boot.
# Ensures the system is ready for Ansible management.
#

set -e

ADMIN_USER="administrator"

# Ensure Python 3 is available for Ansible
if ! command -v python3 &>/dev/null; then
    apt-get update -qq
    apt-get install -y python3
fi

# Ensure SSH is running
if ! systemctl is-active --quiet ssh; then
    systemctl enable ssh
    systemctl start ssh
fi

# Verify admin SSH key is in place
if [ ! -f /home/${ADMIN_USER}/.ssh/authorized_keys ]; then
    mkdir -p /home/${ADMIN_USER}/.ssh
    chmod 700 /home/${ADMIN_USER}/.ssh
    echo "WARNING: No authorized_keys found for ${ADMIN_USER}. Ansible access may fail."
fi

echo "Post-install complete. System is ready for Ansible configuration."
