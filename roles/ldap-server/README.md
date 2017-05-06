# INCOMPLETE #
Just a stub atm

# IMPORTANT
Needs to copy CTTB CA private key manually beforehand.
File name: cakey.pem, to be copied into /etc/ssl/private/.

We do not store it in ansible git tree to keep it private and secure.
You can copy ldap-srv:/etc/ssl/private/cakey.pem, or if that
host is down, theoverseer:~administrator/cakey.pem.

# OVERVIEW
This role contains code to set up an LDAP server.

An example to run it:

1. On asus-test, run:

    sudo role-cleanup.sh

2. Then on the ansible execution machine such as rui-desktop, run:

    utils/ar asus-test ldap-server -e 'ldap_admin_password=amituofo' 
