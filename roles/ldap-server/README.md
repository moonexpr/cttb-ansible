# INCOMPLETE #
Just a stub atm

# IMPORTANT
Needs to copy CTTB CA private key manually beforehand. We did not
store it in ansible git tree to keep it private and secure.
Copy the file /etc/ssl/private/cakey.pem from ldap-srv, or if that
host is down, from theoverseer:~administrator/ldap-srv-cakey.pem.


# OVERVIEW
This role contains code to setup an LDAP server.

An example to run it:

    utils/ar asus-test ldap-server -e 'ldap_admin_password=amituofo' 
