#!/bin/bash

# Clean vars to avoid potential file descriptor issues
unset DEBCONF_REDIR
unset DEBCONF_FRONTEND
unset DEBIAN_HAS_FRONTEND
unset DEBIAN_FRONTEND

TASKSEL=$1

apt-get install -y openssh-server python-minimal >> /var/log/preseed.log

# install admin ssh key for unattended operations
mkdir /home/administrator/.ssh
chmod 700 /home/administrator/.ssh
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDYi3OOvRQAJnIZk+nTH15aJs0AOVSLaSN6TH+zrdyaRGk6XwrbvLoCiyGOveOt4TcwmOzgyrXg9p1Vy0gcd2pjN+fDbO07ftwPGtuSfbvShvnwYaRPzF1IcBEBMeml/e05Naw8Q0KhZbuGXnCHvEDM2QArw9qD/a77kEV9vxrhJaOUOFkdVx1gsU/dAjQikZzD+Sag7JhtSYIpZupA+YbD1K0dRYUdE9dm3yTUUFmWM3nCCpj8kpU+TWjFeG2M4ilWym7Y81tk3CgI3vzRZRkA395IZlpP1FKNjAlNsit8YuldRvgrYXjPH3TcM1XkLFL4k6EJTjwsM5oWC4o9TriFJRTN75MxGgs72tZcgwlN2W+qkGAGAAYMvSqCBPIXuVCp+3ixuECgnJ3pYq48x8J5DmTn6i93Q9eAv7Xj8B9shts8MlrwGzMBHqjEu/CFfJAHtsLmJ34vvfM0kTFp6Du/K7WnYAuBvB4agMSMBAKy3+9ij5r1+hOxEv7rPkJvlFTECYLvEmNGXOSthuKLEHarlAH21YB1+aP5GwdrypLlYifXYXbQyf/nc/sebyleA3yHs99OLxxW3SCFOqvWxRH7kV/i56Ei8JFxAASauQMy/jXT/FgnIKYae46c7ZJ9jTgfsrhZ1OSQ9oUqzyAS3ugUa5QW3uMEpfnXVxt/EnwnOw== ansible@cttb.us" > /home/administrator/.ssh/authorized_keys
chown -R administrator: /home/administrator/.ssh

# get ssh started so I can run ansible
mkdir /var/run/sshd
/usr/sbin/sshd -4 -p22

if [ $TASKSEL != "none" ]
then
  tasksel install $TASKSEL
fi
# to allow ansible to work
#echo "administrator ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/administrator
#chmod 0440 /etc/sudoers.d/administrator
